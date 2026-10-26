fn main() -> impl std::process::Termination {
    anki::sync::http_server::SimpleServer::run()
}
