#!/bin/bash

myversion=$(rpm -q --queryformat "%{VERSION}" openssh-server | grep -o '^[[:digit:]]*\.[[:digit:]]*')

echo "sshd_version=$myversion"
