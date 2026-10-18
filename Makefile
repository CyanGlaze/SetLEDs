setleds: main.c main.h Info.plist
	$(CC) -Wall -o $@ main.c -framework Foundation -framework IOKit \
	    -Wl,-sectcreate,__TEXT,__info_plist,Info.plist
	codesign -s - $@ 2>/dev/null || true

clean :
	rm -f setleds

all : setleds

