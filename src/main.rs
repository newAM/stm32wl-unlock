use core::fmt;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context};
use clap::Parser;
use probe_rs::{
    probe::{list::Lister, DebugProbeInfo, DebugProbeSelector, Probe},
    Core, MemoryInterface, Session, Target,
};

const FLASH_KEYR_ADDR: u64 = 0x5800_4008;
const FLASH_OPTKEYR_ADDR: u64 = 0x5800_400C;
const FLASH_SR_ADDR: u64 = 0x5800_4010;
const FLASH_CR_ADDR: u64 = 0x5800_4014;
const FLASH_OPTR_ADDR: u64 = 0x5800_4020;
const FLASH_PCROP1AER_ADDR: u64 = 0x5800_4028;

const PCROP_RDP_MASK: u32 = 1 << 31;
const OPTSTRT_MASK: u32 = 1 << 17;
const BSY_MASK: u32 = 1 << 16;
const PESD_MASK: u32 = 1 << 19;

/// Readout protection level
#[derive(PartialEq, Eq)]
enum Rdp {
    /// Level 0, readout protection not active
    Lvl0,
    /// Level 1, memories readout protection active
    Lvl1,
    /// Level 2, chip readout protection active
    Lvl2,
}

impl From<u8> for Rdp {
    fn from(x: u8) -> Self {
        match x {
            0xAA => Self::Lvl0,
            0xCC => Self::Lvl2,
            _ => Self::Lvl1,
        }
    }
}

impl fmt::Display for Rdp {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Rdp::Lvl0 => write!(f, "0, readout protection not active"),
            Rdp::Lvl1 => write!(f, "1, memories readout protection active"),
            Rdp::Lvl2 => write!(f, "2, chip readout protection active"),
        }
    }
}

#[derive(Parser)]
#[clap(about, version, author)]
struct Args {
    /// Probe to use, 'VID:PID' or 'VID:PID:Serial'.
    #[clap(value_enum, value_parser)]
    probe: Option<DebugProbeSelector>,
    /// Connect to the target under reset
    #[clap(long, action)]
    connect_under_reset: bool,
}

fn target() -> Target {
    probe_rs::config::get_target_by_name("STM32WLE5JCIx").unwrap()
}

fn set_pcrop_rdp(core: &mut Core) -> anyhow::Result<()> {
    let pcrop1aer: u32 = core
        .read_word_32(FLASH_PCROP1AER_ADDR)
        .context("failed to read FLASH_PCROP1AER")?;

    log::info!("pcrop1aer=0x{pcrop1aer:X}");

    if pcrop1aer & PCROP_RDP_MASK != PCROP_RDP_MASK {
        core.write_word_32(FLASH_PCROP1AER_ADDR, pcrop1aer | PCROP_RDP_MASK)
            .context("failed to write FLASH_PCROP1AER")?;
    }

    Ok(())
}

fn set_optstrt(core: &mut Core) -> anyhow::Result<()> {
    let flash_cr: u32 = core
        .read_word_32(FLASH_CR_ADDR)
        .context("failed to read FLASH_CR")?;

    log::info!("flash_cr=0x{flash_cr:X}");

    core.write_word_32(FLASH_CR_ADDR, flash_cr | OPTSTRT_MASK)
        .context("failed to write FLASH_CR")?;
    core.flush().context("failed to flush")?;

    Ok(())
}

fn unlock_flash(core: &mut Core) -> anyhow::Result<()> {
    core.write_word_32(FLASH_KEYR_ADDR, 0x4567_0123)
        .context("failed to write key1 to FLASH_KEYR")?;
    core.write_word_32(FLASH_KEYR_ADDR, 0xCDEF_89AB)
        .context("failed to write key2 to FLASH_KEYR")?;
    core.flush().context("failed to flush")?;

    core.write_word_32(FLASH_OPTKEYR_ADDR, 0x0819_2A3B)
        .context("failed to write key1 to FLASH_OPTKEYR")?;
    core.write_word_32(FLASH_OPTKEYR_ADDR, 0x4C5D_6E7F)
        .context("failed to write key2 to FLASH_OPTKEYR")?;
    core.flush().context("failed to flush")?;

    Ok(())
}

fn main() -> anyhow::Result<()> {
    env_logger::init();

    let args: Args = Args::parse();

    let lister: Lister = Lister::new();
    let probe: Probe = match args.probe {
        Some(selector) => lister.open(selector),
        None => {
            let probe_list: Vec<DebugProbeInfo> = lister.list_all();
            match probe_list.len() {
                0 => return Err(anyhow!("no probes found")),
                1 => probe_list.first().unwrap().open(),
                _ => {
                    println!("the following probes were found:");
                    probe_list
                        .iter()
                        .enumerate()
                        .for_each(|(idx, info)| println!("[{idx}] {info:?}"));
                    return Err(anyhow!(
                        "more than one probe found; use --probe to specify which one to use"
                    ));
                }
            }
        }
    }
    .context("failed to open probe")?;

    let mut session: Session = probe
        .attach(target(), probe_rs::Permissions::new().allow_erase_all())
        .context("failed attach to chip")?;
    let mut core: Core = session.core(0).context("failed to attach to core 0")?;

    let flash_optr: u32 = core
        .read_word_32(FLASH_OPTR_ADDR)
        .context("failed to read FLASH_OPTR")?;
    log::info!("flash_optr=0x{flash_optr:X}");

    let rdp: Rdp = Rdp::from(flash_optr as u8);

    println!("Current readout protection is level {rdp}");

    match rdp {
        Rdp::Lvl0 => {
            println!("Nothing to do, chip is already unlocked");
            Ok(())
        }
        Rdp::Lvl1 => {
            unlock_flash(&mut core).context("failed to unlock flash")?;

            // set the pcrop fit to perform a mass erase when the RDP level is
            // decreased from 1 to 0
            set_pcrop_rdp(&mut core).context("failed to set PCROP_RDP")?;

            // set RDP to level 0
            core.write_word_32(FLASH_OPTR_ADDR, (flash_optr & 0xFFFF_FF00) | 0xAA)
                .context("failed to write FLASH_OPTR")?;

            // check flash is ready to be erased
            let flash_sr: u32 = core
                .read_word_32(FLASH_SR_ADDR)
                .context("failed to read FLASH_SR")?;
            log::info!("flash_sr=0x{flash_sr:X}");
            if flash_sr & BSY_MASK != 0 {
                return Err(anyhow!("flash is busy"));
            }
            if flash_sr & PESD_MASK != 0 {
                return Err(anyhow!("program erase suspend is set"));
            }

            // start options programming
            set_optstrt(&mut core).context("failed to set OPTSTRT")?;

            // wait for BSY to clear
            let start: Instant = Instant::now();
            loop {
                let flash_sr: u32 = core
                    .read_word_32(FLASH_SR_ADDR)
                    .context("failed to read FLASH_SR")?;
                let elapsed: Duration = Instant::now().duration_since(start);
                if flash_sr & BSY_MASK == 0 {
                    println!("erase duration: {elapsed:?}");
                    break;
                }

                if elapsed > Duration::from_secs(30) {
                    return Err(anyhow!("timeout during erase"));
                }
            }

            println!("flash protection set to level {}", Rdp::Lvl0);
            Ok(())
        }
        Rdp::Lvl2 => Err(anyhow!("RDP level 2 cannot be removed")),
    }
}

#[cfg(test)]
mod test {
    #[test]
    fn target() {
        super::target();
    }
}
