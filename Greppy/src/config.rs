use std::process;

pub struct Config {
  pub text_to_search: String,
  pub case_insensitive: bool
}

impl Config {
  pub fn new(args:&[String]) -> Config {
    let mut case_insensitive = false;
    let mut pattern: Option<String> = None;

    for arg in args.iter().skip(1) {
        if arg == "-i" {
            case_insensitive = true;
        }else if pattern.is_none(){
            pattern = if case_insensitive { Some(arg.to_lowercase()) } else { Some(arg.clone()) };
        }
    }
    
    let text_to_search = pattern.unwrap_or_else(|| {
      eprintln!("Usage: greppy <pattern>");
      process::exit(1);
    });

    Config { text_to_search, case_insensitive }
  }
}