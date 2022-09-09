# yubikey-luks
Yubikey LUKS setup for Ubuntu 22.04 LTS

## Install yubikey-personalization and yubikey-luks
```
$ sudo apt install yubikey-luks yubikey-personalization
```

## Plug in the YubiKey and set up slot 2 for challenge response
```
$ ykpersonalize -2 -ochal-resp -ochal-hmac -ohmac-lt64 -oserial-api-visible
```

## Run lsblk if you are unsure of the name of your LUKS partition
```
root@laptop:~# lsblk
NAME                  MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
nvme0n1               259:0    0 953,9G  0 disk  
├─nvme0n1p1           259:1    0   512M  0 part  /boot/efi
├─nvme0n1p2           259:2    0   732M  0 part  /boot
└─nvme0n1p3           259:3    0 952,7G  0 part  
  └─nvme0n1p3_crypt   253:0    0 952,6G  0 crypt 
    ├─vgubuntu-root   253:1    0 930,4G  0 lvm   /
    └─vgubuntu-swap_1 253:2    0   976M  0 lvm   [SWAP]
```
In this case the name is *nvme0n1*

## Make sure keyslot 1 is empty
```
$ sudo cryptsetup luksDump /dev/nvme0n1p3
LUKS header information
Version:       	2
Epoch:         	4
Metadata area: 	16384 [bytes]
Keyslots area: 	16744448 [bytes]
UUID:          	ca5b1f00-27be-4058-af39-8e33ba9b533a
Label:         	(no label)
Subsystem:     	(no subsystem)
Flags:       	(no flags)

Data segments:
  0: crypt
	offset: 16777216 [bytes]
	length: (whole device)
	cipher: aes-xts-plain64
	sector: 512 [bytes]

Keyslots:
  0: luks2
	  Key:        512 bits
	  Priority:   normal
	  Cipher:     aes-xts-plain64
	  Cipher key: 512 bits
	  PBKDF:      argon2i
	  Time cost:  8
	  Memory:     1048576
	  Threads:    4
	  Salt:       XX XX XX XX XX XX XX XX XX XX XX XX XX XX XX XX
              XX XX XX XX XX XX XX XX XX XX XX XX XX XX XX XX 
	  AF stripes: 4000
	  AF hash:    sha256
	  Area offset:32768 [bytes]
	  Area length:258048 [bytes]
	  Digest ID:  0
  
Tokens:

```

There should be no *1: luks2* entry.

## Assign the YubiKey to slot 1
```
$ sudo yubikey-luks-enroll -d /dev/nvme0n1p3 -s 1
```
Remember the challenge/passphrase you used!

## Update */etc/cryptab*

Change from
```
nvme0n1p3_crypt UUID=abcdefab-1234-abcd-abcd-123456789abc none luks,discard
```

To this
```
nvme0n1p3_crypt UUID=abcdefab-1234-abcd-abcd-123456789abc none luks,discard,keyscript=/usr/share/yubikey-luks/ykluks-keyscript
```
(the value *abcdefab-1234-abcd-abcd-123456789abc* will be the UUID of your disk) 

## Boot without user interaction
If you want the machine to be unlocked only by the YubiKey, you can add the challenge/passphrase from the enrollment step to */etc/ykluks.cfg*

Add a line with the challenge
```
YUBIKEY_CHALLENGE="YOUR PASSPHRASE HERE"
```

# IMPORTANT:

Replace the */usr/share/yubikey-luks/ykluks-keyscript* from the yubikey-luks package with the file from this repo.
The file from the 22.04 is broken ( the YUBIKEY_CHALLENGE part do not work! )

## Update the *initramfs*
```
$sudo update-initramfs -u
```

## Reboot!

Links:

[Using a YubiKey as authentication for an encrypted disk](https://www.endpointdev.com/blog/2022/03/disk-decryption-yubikey/)

[https://github.com/cornelinux/yubikey-luks](https://github.com/cornelinux/yubikey-luks)
