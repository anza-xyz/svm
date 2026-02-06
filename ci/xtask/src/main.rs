use {
    anyhow::Result,
    clap::{Args, Parser, Subcommand},
    log::error,
};

mod commands;

#[derive(Parser)]
#[command(name = "xtask", about = "SVM build and release tasks", version)]
struct Xtask {
    #[command(flatten)]
    pub global: GlobalOptions,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    #[command(about = "Publish crates")]
    Publish(commands::publish::CommandArgs),
}

#[derive(Args, Debug)]
pub struct GlobalOptions {
    #[arg(short, long, global = true)]
    pub verbose: bool,
}

#[tokio::main]
async fn main() {
    if let Err(err) = try_main().await {
        error!("Error: {err}");
        for (i, cause) in err.chain().skip(1).enumerate() {
            error!("  {}: {}", i.saturating_add(1), cause);
        }
        std::process::exit(1);
    }
}

async fn try_main() -> Result<()> {
    let xtask = Xtask::parse();

    if xtask.global.verbose {
        std::env::set_var("RUST_LOG", "debug");
    } else {
        std::env::set_var("RUST_LOG", "info");
    }
    env_logger::init();

    match xtask.command {
        Commands::Publish(args) => {
            commands::publish::run(args)?;
        }
    }

    Ok(())
}
