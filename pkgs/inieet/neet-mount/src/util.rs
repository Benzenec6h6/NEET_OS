use std::io;
use std::process::Command;

pub(crate) fn fatal(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::Other, msg)
}

pub(crate) fn run(cmd: &mut Command) -> io::Result<()> {
    let status = cmd.status()?;
    if status.success() {
        Ok(())
    } else {
        Err(fatal(format!("{cmd:?} exited with {status}")))
    }
}
