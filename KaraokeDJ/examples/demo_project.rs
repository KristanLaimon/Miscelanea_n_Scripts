fn main() {
    let directory = std::path::Path::new("examples");
    let project = karaoke_maker::model::Project::demo();
    std::fs::write(directory.join("demo.kdj"), project.encode().unwrap()).unwrap();
    std::fs::write(
        directory.join("demo.lrc"),
        karaoke_maker::model::lrc(&project.lyrics),
    )
    .unwrap();
}
