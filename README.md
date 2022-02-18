# stm32wl-unlock

Unlock the flash on STM32WL microcontrollers.

This is useful for the seeed studio STM32WL modules that have flash protection bits set.

⚠️ This will destroy the flash contents on your chip, in the case of seeed modules this process is not reversible. ⚠️

## Installation

1. Install [rustup](https://rustup.rs/)
2. `cargo install --git https://github.com/newAM/stm32wl-unlock.git`

## Example

For the seeed modules you will want to hold the reset button for the entire process.

```console
$ stm32wl-unlock
Current readout protection is level 1, memories readout protection active
Flash protection set to level 0, readout protection not active
```
