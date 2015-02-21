#!/bin/sh

for rpmpak in `rpm -qa`; do
    yumdownloader $rpmpak --destdir=packages
done
