# EAGER
EAGER is a fuzzer that systematically improves Android kernel fuzzing through module-aware corpus generation. 
EAGER follows a three-phase pipeline: it first extracts interface definitions from the LLVM bitcode of loadable kernel modules; then infers parameter constraints via symbolic execution; and finally synthesizes valid corpus entries while ensuring correct module initialization through dependency-aware loading. 

## Build
### Install Prerequisites
Basic dependencies install (take for example on debain or ubuntu):
```
sudo apt update
sudo apt install make gcc flex bison libncurses-dev libelf-dev libssl-dev
```

### Install golang

We use golang in EAGER, so make sure your golang is avaliable before build EAGER.
```
wget https://dl.google.com/go/go1.22.4.linux-amd64.tar.gz
tar -xf go1.22.4.linux-amd64.tar.gz
mv go goroot
mkdir gopath
export GOPATH=`pwd`/gopath
export GOROOT=`pwd`/goroot
export PATH=$GOPATH/bin:$PATH
export PATH=$GOROOT/bin:$PATH 
```

### Prepare Android Kernel

In here we use Android kernel(16-6.12) as an example.
First, we need to download the source code.
```
# Download the repo tool
mkdir ~/bin
PATH=~/bin:$PATH
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo

# Download the source code
repo init -u https://android.googlesource.com/kernel/manifest -b android16-6.12
repo sync
```

Then, configure the Android kernel use `bazel run //common:kernel_aarch64_config menuconfig` to modify the kernel configuration manually or you can directly modify the `.config` file.
```
CONFIG_KCOV=y
CONFIG_KASAN=y
CONFIG_KASAN_INLINE=y
CONFIG_DEBUG_INFO=y
CONFIG_CMDLINE="console=ttyAMA0"
CONFIG_KCOV_INSTRUMENT_ALL=y
CONFIG_KCOV_ENABLE_COMPARISONS=y
CONFIG_DEBUG_FS=y
CONFIG_NET_9P=y
CONFIG_NET_9P_VIRTIO=y
CONFIG_DEBUG_KMEMLEAK=y
DEBUG_INFO_DWARF4=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_CGROUP_PIDS=y
CONFIG_MEMCG=y
CONFIG_USER_NS=y
CONFIG_CONFIGFS_FS=y
CONFIG_SECURITYFS=y
CONFIG_RANDOMIZE_BASE=n
CONFIG_FAULT_INJECTION=y
CONFIG_FAULT_INJECTION_DEBUG_FS=y
CONFIG_FAULT_INJECTION_USERCOPY=y
CONFIG_FAILSLAB=y
CONFIG_FAIL_PAGE_ALLOC=y
CONFIG_FAIL_MAKE_REQUEST=y
CONFIG_FAIL_IO_TIMEOUT=y
CONFIG_FAIL_FUTEX=y
CONFIG_PROVE_LOCKING=y
CONFIG_DEBUG_ATOMIC_SLEEP=y
CONFIG_PROVE_RCU=y
CONFIG_DEBUG_VM=y
CONFIG_FORTIFY_SOURCE=y
CONFIG_HARDENED_USERCOPY=y
CONFIG_LOCKUP_DETECTOR=y
CONFIG_SOFTLOCKUP_DETECTOR=y
CONFIG_HARDLOCKUP_DETECTOR=y
CONFIG_BOOTPARAM_HARDLOCKUP_PANIC=y
CONFIG_DETECT_HUNG_TASK=y
CONFIG_WQ_WATCHDOG=y
CONFIG_DEFAULT_HUNG_TASK_TIMEOUT=140
CONFIG_RCU_CPU_STALL_TIMEOUT=100
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_DEBUG_INFO_BTF=y
CONFIG_DEBUG_KERNEL=y
CONFIG_NET=y
CONFIG_PACKET=y
CONFIG_UNIX=y
CONFIG_9P_FS=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_BLK=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_HW_RANDOM_VIRTIO=y
CONFIG_DEBUG_INFO_COMPRESSED=n
DEBUG_INFO_COMPRESSED_ZSTD=n
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
MODULE_DEBUG_AUTOLOAD_DUPS=n
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_ALL=y
```

Use `bazel build //common:kernel_aarch64` to make the kernel. All results are loacted in the `bazel-bin` directory.

### Prepare rootfs
We will use buildroot to create the disk image. You can obtain buildroot from [here](https://buildroot.uclibc.org/download.html). Extract the tarball and perform a make menuconfig inside it. Choose the following options.
```
Target options
    Target Architecture - Aarch64 (little endian)
Toolchain type
    External toolchain - Linaro AArch64
System Configuration
[*] Enable root login with password
        ( ) Root password = set your password using this option
[*] Run a getty (login prompt) after boot  --->
    TTY port - ttyAMA0
[*] remount root filesystem read-write during boot                                   
	(eth0) Network interface to configure through DHCP
(/path/to/overlay) Root filesystem overlay directories
Target packages
    [*]   Show packages that are also provided by busybox
    Networking applications
        [*] dhcpcd
        [*] iproute2
        [*] openssh
Filesystem images
    [*] ext2/3/4 root filesystem
        ext2/3/4 variant - ext4
        exact size in blocks - 512M
    [*] tar the root filesystem
```
Put all the `.ko` files to /path/to/overlay and then run make.

After the build, confirm that output/images/rootfs.ext4 exists.

### Boot Manually
You should be able to start up the kernel as follows.
```
 /path/to/qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a57 \
  -nographic -smp 1 \
  -hda /path/to/rootfs.ext4 \
  -kernel /path/to/arch/arm64/boot/Image \
  -append "console=ttyAMA0 root=/dev/vda oops=panic panic_on_warn=1 panic=-1 ftrace_dump_on_oops=orig_cpu debug earlyprintk=serial slub_debug=UZ" \
  -m 2048 \
  -net user,hostfwd=tcp::10023-:22 -net nic
```

### Set up the QEMU Disk

Install QEMU: `sudo apt-get install qemu-system-x86`
Now that we have a shell, let us add a few lines to existing init scripts so that they are executed each time Syzkaller brings up the VM.

At the top of /etc/init.d/S50sshd add the following lines:
```
ifconfig eth0 up
dhcpcd
mount -t debugfs none /sys/kernel/debug
chmod 777 /sys/kernel/debug/kcov
Comment out the line
```
```
/usr/bin/ssh-keygen -A
```
Next we set up ssh. Create an ssh keypair locally and copy the public key to `/authorized_keys` in `/.` Ensure that you do not set a passphrase when creating this key.

Open `/etc/ssh/sshd_config` and modify the following lines as shown below.
```
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile      /authorized_keys
PasswordAuthentication yes
```
Reboot the machine, and ensure that you can ssh from host to guest as.`ssh -i /path/to/id_rsa root@localhost -p 10023`

### Run EAGER

Create a workdir and move the corpus.db in it and then

```
./syz-manager -config=config.json
```



## Experiment Results

### Host Machine System Configuration
```
CPU: 128 cores
Memory: 32 GB
Ubuntu 20.04.4 LTS
```

### Virtual Machine 
```
2 core CPU + 2GB Memory
```

### Target Android Kernel Version
We use four AOSP kernel versions(Android 16-6.12, Android 15-6.6, Android 14-6.1, and Android 14-5.15), Xiaomi HyperOS, and Huawei OpenHarmony as fuzzing targets. All kernel versions were compiled with the same configuration, with both KCOV and KASAN enabled, to collect coverage data and detect memory errors. For KCSAN experiments, identical settings were used in both baseline and experimental groups to ensure fairnes

### Coverage Over 24h
![image-20260113004943545](./imgs/image-20260113004943545.png)


### New Bug Found
| No.  | Crashed Functions           | Bug Types         | Bug Descriptions                                             | Status    |
| ---- | --------------------------- | ----------------- | ------------------------------------------------------------ | --------- |
| 1    | pl011_console_write()       | logic error       | recursive locking in pl011_console_write causes spinlock violation | Reported  |
| 2    | step_into()                 | null ptr deref    | step_into dereference during path resolution triggers fault  | Reported  |
| 3    | process_one_work()          | null ptr deref    | null pointer in process_one_work from lockdep tracing        | Reported  |
| 4    | wg_packet_encrypt_worker()  | deadlock          | wg_packet_encrypt_worker triggers RCU stall on CPU           | Reported  |
| 5    | fs_bdev_sync()              | deadlock          | fs_bdev_sync blocks due to superblock mutex contention       | Confirmed |
| 6    | rescuer_thread()            | deadlock          | mutex contention in rescuer_thread blocks worker threads     | Confirmed |
| 7    | ihold()                     | null ptr deref    | simple_rmdir causes null pointer in ihold function           | Reported  |
| 8    | rtnl_newlink()              | deadlock          | rtnl_newlink causes system deadlock via rtnl_mutex           | Confirmed |
| 9    | gc_worker()                 | deadlock          | gc_worker hard lockup from connection tracking race          | Confirmed |
| 10   | dir_mkdir()                 | deadlock          | dir_mkdir recursive lock causes directory deadlock           | Confirmed |
| 11   | incfs_lookup_dentry()       | deadlock          | incfs_lookup_dentry with lookup_slow causes lock loop        | Confirmed |
| 12   | vfs_rmdir()                 | deadlock          | vfs_rmdir with do_rmdir causes circular inode lock           | Confirmed |
| 13   | event_function()            | logic error       | event_function control error causes remote CPU fault         | Reported  |
| 14   | incfs_realloc_mount_info()  | memory corruption | incfs_realloc_mount_info failure corrupts memory allocator   | Confirmed |
| 15   | drop_nlink()                | logic error       | drop_nlink miscounts inode links in shmem_rmdir              | Reported  |
| 16   | ___rmqueue_pcplist()        | logic error       | ___rmqueue_pcplist causes invalid wait with mmap_lock        | Reported  |
| 17   | blk_rq_timed_out_timer()    | deadlock          | blk_rq_timed_out_timer triggers CPU soft lockup              | Confirmed |
| 18   | incfs_setattr()             | deadlock          | incfs_setattr missing nesting annotation triggers deadlock   | Reported  |
| 19   | do_sve_acc()                | logic error       | invalid access in SVE accumulator context handling triggers kernel crash | Reported  |
| 20   | may_delete()                | logic error       | may_delete logic fails on invalid directory entry            | Reported  |
| 21   | tls_proc_fini()             | memory corruption | improper removal of proc entry tls_stat causes memory corruption | Confirmed |
| 22   | remove_proc_entry()         | logic error       | improper cleanup in procfs removal triggers crash            | Confirmed |
| 23   | kthread()                   | deadlock          | blocked kworker thread in kthread() causes indefinite scheduling stall | Confirmed |
| 24   | GetSortedChildren()         | logic error       | use of an uninitialized value in GetSortedChildren()         | Confirmed |
| 25   | GetChildren()               | logic error       | lack of a depth limit leads to a stack overflow during recursion | Confirmed |
| 26   | CollectAllChildren()        | logic error       | cyclic tree structure leads to a stack overflow during recursion | Confirmed |
| 27   | HasDisappearingTransition() | logic error       | cyclic tree structure leads to a stack overflow during recursion | Confirmed |
