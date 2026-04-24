#!/bin/sh
#
# Copyright (c) 2011-present Sonatype, Inc. All rights reserved.
# Includes the third-party code listed at http://links.sonatype.com/products/clm/attributions.
# "Sonatype" is a trademark of Sonatype, Inc.
#

USER_ID=$(id -u)
if [[ ${USER_UID} != ${USER_ID} ]]; then
    sed "s@${USER_NAME}:x:\${USER_ID}:@${USER_NAME}:x:${USER_ID}:@g" /etc/passwd.template > /etc/passwd
fi
exec "$@"
