shell=$shell
folder=$(cd "$(dirname $0)"|| exit; pwd)

for f in $(ls $folder/08/*.S)
do
    echo "compile $(basename $f)"
    fn=$(echo $f | cut -d . -f1)
    nasm -f bin $f -o $fn.bin
done
echo "done..."