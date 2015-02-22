#!/bin/sh

ISODIR=../iso

#0: Prepare files
# mkdir -p ../iso
# cp ../centos7/.discinfo ../iso
# cp ../centos7/.treeinfo ../iso
# cp -r ../centos7/Packages ../iso
# cp -r ../centos7/images ../iso
# cp -r ../centos7/isolinux ../iso
# cp -r ../centos7/LiveOS ../iso

# OS packages
rm -rf $ISODIR/repodata/
/bin/cp comps.xml $ISODIR
/bin/cp install.sh $ISODIR
createrepo -g comps.xml $ISODIR

rm -rf $ISODIR/ks
mkdir -p $ISODIR/ks
/bin/cp ks.cfg $ISODIR/ks
/bin/cp isolinux.cfg $ISODIR/isolinux

mkisofs -o monitor.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -R -J -V "monitor_install" -v -T $ISODIR
