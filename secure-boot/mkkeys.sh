#!/bin/bash
# Based on:
#   http://www.rodsbooks.com/efi-bootloaders/controlling-sb.html
#   https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide/Configuring_Secure_Boot
# Copyright (c) 2015 by Roderick W. Smith
# Copyright (c) 2019 by Michal Gawlik
# Licensed under the terms of the GPL v3

[ -f PK.key ] && { echo "Keys already generated! Press Enter twice to continue and overwrite, CTRL+C to exit."; read; read; }

read -p "Enter a Common Name to embed in the keys: " NAME
CERT_EXTRA=""
#CERT_EXTRA="C=PL/O=Dexter's Laboratories/"  # finish with '/' !


set -x
openssl req -new -x509 -newkey rsa:2048 -subj "/${CERT_EXTRA}CN=$NAME Platform Key/"       -keyout PK.key  -out PK.crt  -days 36500 -nodes -sha256
openssl req -new -x509 -newkey rsa:2048 -subj "/${CERT_EXTRA}CN=$NAME Key-Exchange Key/"   -keyout KEK.key -out KEK.crt -days 36500 -nodes -sha256
openssl req -new -x509 -newkey rsa:2048 -subj "/${CERT_EXTRA}CN=$NAME Kernel Signing Key/" -keyout db.key  -out db.crt  -days 36500 -nodes -sha256
cat PK.key  PK.crt  > PK.prv
cat KEK.key KEK.crt > KEK.prv
cat db.key  db.crt  > db.prv
chmod -v 0400 *.key *.prv

openssl x509 -in PK.crt  -out PK.cer  -outform DER
openssl x509 -in KEK.crt -out KEK.cer -outform DER
openssl x509 -in db.crt  -out db.cer  -outform DER

GUID="$(uuidgen)"
echo $GUID > myGUID.txt

cert-to-efi-sig-list -g $GUID PK.crt  PK.esl
cert-to-efi-sig-list -g $GUID KEK.crt KEK.esl
cert-to-efi-sig-list -g $GUID db.crt  db.esl
rm -f noPK.esl
touch noPK.esl

DATE="$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')"
sign-efi-sig-list    -t "$DATE" -k PK.key  -c PK.crt  PK  PK.esl       PK.auth
sign-efi-sig-list    -t "$DATE" -k PK.key  -c PK.crt  PK  noPK.esl     noPK.auth
sign-efi-sig-list    -t "$DATE" -k PK.key  -c PK.crt  KEK KEK.esl      KEK.auth
sign-efi-sig-list -a -t "$DATE" -k PK.key  -c PK.crt  KEK KEK.esl      KEK.append.auth
sign-efi-sig-list    -t "$DATE" -k KEK.key -c KEK.crt db  db.esl       db.auth
sign-efi-sig-list -a -t "$DATE" -k KEK.key -c KEK.crt db  db.esl       db.append.auth
sign-efi-sig-list    -t "$DATE" -k KEK.key -c KEK.crt dbx orig_dbx.esl orig_dbx.auth

cat orig_KEK.esl KEK.esl > KEK.compound.esl
cat orig_db.esl  db.esl  > db.compound.esl
sign-efi-sig-list    -t "$DATE" -k PK.key  -c PK.crt  KEK KEK.compound.esl KEK.compound.auth
sign-efi-sig-list    -t "$DATE" -k KEK.key -c KEK.crt db  db.compound.esl  db.compound.auth
