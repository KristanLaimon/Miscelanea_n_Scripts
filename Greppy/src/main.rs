use std::{env, io, io::BufRead};
mod color;

mod config;
use config::Config;

fn main()  {
    let args: Vec<String> = env::args().collect();
    let config: Config  = Config::new(&args);

    let stdin = io::stdin();
    let mut i:i32 = 0;
    for line in stdin.lock().lines().into_iter(){
        match line {
            Ok(line) => {
                let lower_line = line.to_lowercase();
                let msg_to_show: Option<String>; 

                if config.case_insensitive {
                    msg_to_show = format_searched_line(&line, &lower_line, &config.text_to_search, color::GREEN);
                }else{
                    msg_to_show = format_searched_line(&line, &line, &config.text_to_search, color::GREEN);
                };

                if let Some(msg) = msg_to_show {
                    i += 1;
                    println!("{}. {}", i, msg);
                }
            }
            Err(e) => {
                println!("Error reading a line from stdin. Error: {:?}", e);
            }
        }
    }
}

fn format_searched_line(original_line: &String, search_line: &String, search_word:&String, color: &'static str) -> Option<String>{
    if let Some(index_at_first_letter) = search_line.find(search_word){
        let after_word_index  = index_at_first_letter + search_word.len();

        let before_word_content = &original_line[..index_at_first_letter];
        let word = &original_line[index_at_first_letter..after_word_index];
        let after_word_content = &original_line[after_word_index..];

        Some(format!("{}{}{}{}{}", before_word_content, color, word, color::RESET, after_word_content))
    }else{
        None
    }
}


