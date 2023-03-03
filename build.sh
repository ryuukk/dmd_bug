#!/usr/bin/env bash

set -e

build() {
	dmd \
	-debug -g \
	-m64 -vcolumns -betterC -w -i -i=-std -i=-core \
	-Igame \
	-Istuff/ \
	stuff/rt/object.d \
	game/app.d \
	-of=game.exe
}

build
./game.exe