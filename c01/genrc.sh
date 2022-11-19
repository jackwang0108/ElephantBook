# check system
sys=$(uname -s)
case $sys in
    Linux)
        os=LINUX
        ;;
    Darwin)
        os=MACOS
        ;;
    FreeBSD)
        os=LINUX
        ;;
    *)
        os=UNKNOWN
        ;;
esac

if [ "$os" == "UNKNOWN" ]; then
    echo "Unknown OS, exit..."
    exit
fi

# get disk image
shell_folder=$(cd "$(dirname $0)" || exit; pwd)
cd $shell_folder
bin_file=$(grep -d skip . * | grep -e 'Binary' | grep -v ':' | awk '{print $3}')
bin_info=($(bximage -func=info $bin_file -q | awk '/geometry/{print $3}' | awk -F '/' '{print $1,$2,$3}'))
echo "Binary file detected: $bin_file, C/H/S: ${bin_info[0]}/${bin_info[1]}/${bin_info[2]}"


echo "Using $os config, writing config to bochsrc.run"
sed \
    -e "s/# $os: //g"\
    -e "s/PATH/$bin_file/g"\
    -e "s/CYLINDERS/${bin_info[0]}/g"\
    -e "s/HEADS/${bin_info[1]}/g"\
    -e "s/SPT/${bin_info[2]}/g"\
    $shell_folder/bochsrc.source  > $shell_folder/bochsrc
echo 'Run `bochs -f bochsrc` to start bochs'
# bochsrc -f bochsrc