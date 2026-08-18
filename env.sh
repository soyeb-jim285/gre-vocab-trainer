# Source before building: `. ./env.sh`
# Arch ships ncurses as libncursesw.so.6; the Swift toolchain links libncurses.so.6.
export PATH="$HOME/.local/share/swiftly/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/share/swiftly/compat:$LD_LIBRARY_PATH"
