use std::{env, fs, path::PathBuf};
use prost_reflect::DescriptorPool;

fn main() {
    // anki_proto build dependency produces this before this script runs.
    let source = anki_proto_gen::descriptors_path();
    let bytes = fs::read(&source).expect("Anki protobuf descriptors");
    let pool = DescriptorPool::decode(bytes.as_slice()).unwrap();
    let (_, services) = anki_proto_gen::get_services(&pool);
    let mut methods = serde_json::Map::new();
    for service in services {
        for method in service.all_methods() {
            let key = format!("{}.{}", service.name.trim_start_matches("Backend"), method.proto.name());
            let mapping = serde_json::json!({
                "service": service.index, "method": method.index,
                "input": method.proto.input().full_name(),
                "output": method.proto.output().full_name()
            });
            methods.insert(key, mapping.clone());
            methods.insert(method.name.clone(), mapping);
        }
    }
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    fs::write(out.join("descriptors.bin"), bytes).unwrap();
    fs::write(out.join("methods.json"), serde_json::to_vec(&methods).unwrap()).unwrap();
    println!("cargo:rerun-if-changed={}", source.display());
}
