shell_folder=$(cd "$(dirname "$0")" || exit; pwd)

# get disk image
shell_folder=$(cd "$(dirname "$0")" || exit; pwd)
cd "$shell_folder" || exit
bin_file=$(grep -d skip . * | grep -e 'Binary' | grep -v ':' | awk '{print $3}')
if [ -z "$bin_file" ]; then
    read -r -p "Binary file not detected, enter the name to create [hd60M.img]:" bin_file
    if [ -z "$bin_file" ]; then
        bin_file="hd60M.img"
    fi
    echo "Generating $bin_file..."
    bximage -q -func=create -hd=60 -imgmode=flat "$shell_folder"/$bin_file
else
    bin_info=($(bximage -func=info $bin_file -q | awk '/geometry/{print $3}' | awk -F '/' '{print $1,$2,$3}'))
    echo "Binary file detected: $bin_file, C/H/S: ${bin_info[0]}/${bin_info[1]}/${bin_info[2]}"
fi
echo "You can run genrc.sh to auto-config bochsrc"

echo "Compiling..."
mkdir -p "$shell_folder"/exe
target=a
# mbr
if ! nasm "$shell_folder"/$target/boot/mbr.S -f bin -o "$shell_folder"/exe/mbr.bin -i "$shell_folder"/$target/boot;
    then
    echo "Compile mbr.S fail!"
    exit
fi
dd if="$shell_folder"/exe/mbr.bin of=$bin_file bs=512 count=1 conv=notrunc
# loader
if nasm "$shell_folder"/$target/boot/loader.S -f bin -o "$shell_folder"/exe/loader.bin -i "$shell_folder"/$target/boot;
    then
    echo "Compile loader.S fail!"
    exit
fi
dd if="$shell_folder"/exe/loader.bin of=$bin_file bs=512 seek=2 conv=notrunc
echo "Done, run genrc.sh to auto-config"