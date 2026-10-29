//! C ABI around the identical Rust engine used by AnkiDroid 2.26.0alpha7.
//! Callers serialize collection operations per handle; progress/abort may run concurrently.
//! Keep handles alive until calls finish,
//! and free each returned string exactly once with ap_string_free.
mod eta;
mod local_sync;

use std::{collections::HashMap, ffi::{CStr, CString, c_char, c_void}, panic::{catch_unwind, AssertUnwindSafe}, sync::LazyLock};
use anki::backend::{Backend, init_backend};
use prost::Message;
use prost_reflect::{DescriptorPool, DynamicMessage};
use serde_json::{Value, json};

static POOL: LazyLock<DescriptorPool> = LazyLock::new(|| DescriptorPool::decode(include_bytes!(concat!(env!("OUT_DIR"), "/descriptors.bin")).as_slice()).unwrap());
static METHODS: LazyLock<HashMap<String, Value>> = LazyLock::new(|| serde_json::from_slice(include_bytes!(concat!(env!("OUT_DIR"), "/methods.json"))).unwrap());

struct BridgeError { message: String, kind: Option<i32> }
impl From<String> for BridgeError {
    fn from(message: String) -> Self { Self { message, kind: None } }
}
impl From<&str> for BridgeError {
    fn from(message: &str) -> Self { message.to_owned().into() }
}
fn output(result: Result<Value, BridgeError>) -> *mut c_char {
    let value = match result { Ok(data) => json!({"ok": data}), Err(error) => json!({"error": error.message, "errorKind": error.kind}) };
    CString::new(value.to_string()).unwrap().into_raw()
}
fn protected(f: impl FnOnce() -> Result<Value, BridgeError>) -> *mut c_char {
    output(catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| Err("Anki engine panicked; reopen the app before continuing".into())))
}
unsafe fn string<'a>(value: *const c_char) -> Result<&'a str, String> {
    if value.is_null() { return Err("null string".into()); }
    CStr::from_ptr(value).to_str().map_err(|e| e.to_string())
}
fn encode(name: &str, json: &str) -> Result<DynamicMessage, String> {
    let descriptor = POOL.get_message_by_name(name).ok_or_else(|| format!("Unknown message: {name}"))?;
    let mut deserializer = serde_json::Deserializer::from_str(json);
    let message = DynamicMessage::deserialize(descriptor, &mut deserializer).map_err(|e| e.to_string())?;
    deserializer.end().map_err(|e| e.to_string())?;
    Ok(message)
}

#[no_mangle]
pub unsafe extern "C" fn ap_open(error_out: *mut *mut c_char) -> *mut c_void {
    open_backend(None, error_out)
}

/// The JSON array configures only this handle's translations. It does not
/// rename existing collection entities or change a running handle's language.
#[no_mangle]
pub unsafe extern "C" fn ap_open_with_languages(languages_json: *const c_char, error_out: *mut *mut c_char) -> *mut c_void {
    open_backend(Some(languages_json), error_out)
}

unsafe fn open_backend(languages_json: Option<*const c_char>, error_out: *mut *mut c_char) -> *mut c_void {
    if !error_out.is_null() { *error_out = std::ptr::null_mut(); }
    fn assert_threadsafe<T: Send + Sync>() {}
    assert_threadsafe::<Backend>();
    let result = catch_unwind(AssertUnwindSafe(|| {
        let languages: Vec<String> = match languages_json {
            None => vec!["ja".to_owned(), "en".to_owned()],
            Some(value) => serde_json::from_str(string(value)?).map_err(|e| e.to_string())?,
        };
        let init = encode("anki.backend.BackendInit", &json!({"preferredLangs": languages}).to_string())?;
        init_backend(&init.encode_to_vec())
    })).unwrap_or_else(|_| Err("Anki initialization panicked".into()));
    match result {
        Ok(backend) => Box::into_raw(Box::new(backend)).cast(),
        Err(error) => { if !error_out.is_null() { *error_out = output(Err(error.into())); } std::ptr::null_mut() }
    }
}

#[no_mangle]
pub unsafe extern "C" fn ap_call(handle: *mut c_void, method: *const c_char, request: *const c_char) -> *mut c_char {
    protected(|| {
        let backend = (handle as *const Backend).as_ref().ok_or("Backend is closed")?;
        let name = string(method)?;
        if name == "_droid/local_sync_status" {
            return local_sync::status(backend).map_err(Into::into);
        }
        if name == "_droid/force_one_way_sync" {
            return local_sync::force_one_way(backend).map_err(Into::into);
        }
        if name == "_droid/eta" {
            return eta::estimate(backend, string(request)?).map_err(Into::into);
        }
        let binary = name.starts_with("_anki/");
        let decode_only = name.starts_with("_decode/");
        let encode_only = name.starts_with("_encode/");
        let lookup = name.strip_prefix("_anki/").or_else(|| name.strip_prefix("_decode/")).or_else(|| name.strip_prefix("_encode/")).unwrap_or(name);
        let mapping = METHODS.get(lookup).ok_or_else(|| format!("Unknown method: {name}"))?;
        if encode_only {
            let response = encode(mapping["output"].as_str().unwrap(), string(request)?)?;
            return Ok(json!({"data": data_encoding::BASE64.encode(&response.encode_to_vec())}));
        }
        let input = if binary || decode_only {
            let envelope: Value = serde_json::from_str(string(request)?).map_err(|e| e.to_string())?;
            data_encoding::BASE64.decode(envelope["data"].as_str().ok_or("missing protobuf data")?.as_bytes()).map_err(|e| e.to_string())?
        } else {
            encode(mapping["input"].as_str().unwrap(), string(request)?)?.encode_to_vec()
        };
        if decode_only {
            let message = DynamicMessage::decode(POOL.get_message_by_name(mapping["input"].as_str().unwrap()).unwrap(), input.as_slice()).map_err(|e| e.to_string())?;
            return serde_json::to_value(message).map_err(|e| e.to_string().into());
        }
        let result = backend.run_service_method(mapping["service"].as_u64().unwrap() as u32, mapping["method"].as_u64().unwrap() as u32, &input);
        let bytes = result.map_err(|bytes| {
            match DynamicMessage::decode(POOL.get_message_by_name("anki.backend.BackendError").unwrap(), bytes.as_slice()) {
                Ok(error) => {
                    let message = error.get_field_by_name("message").unwrap().as_ref().as_str().unwrap_or("Anki error").to_owned();
                    let kind = match error.get_field_by_name("kind").unwrap().as_ref() { prost_reflect::Value::EnumNumber(number) => Some(*number), _ => None };
                    BridgeError { message, kind }
                },
                Err(_) => "Failed to decode Anki error".into()
            }
        })?;
        if binary { return Ok(json!({"data": data_encoding::BASE64.encode(&bytes)})); }
        let response = DynamicMessage::decode(POOL.get_message_by_name(mapping["output"].as_str().unwrap()).unwrap(), bytes.as_slice()).map_err(|e| e.to_string())?;
        serde_json::to_value(response).map_err(|e| e.to_string().into())
    })
}

#[no_mangle]
pub unsafe extern "C" fn ap_close(handle: *mut c_void) {
    if !handle.is_null() { let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(handle as *mut Backend)))); }
}
#[no_mangle]
pub unsafe extern "C" fn ap_string_free(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}
