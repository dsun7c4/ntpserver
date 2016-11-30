#ifndef PETALINUX
#$(error You must source the petalinux/settings.sh script before working with PetaLinux)
#endif

#include apps.common.mk

PEEK = peek
POKE = poke

# Add any other object files to this list below
PEEK_OBJS = peek.o
POKE_OBJS = poke.o

all: $(PEEK) $(POKE)

$(POKE): $(POKE_OBJS)
	$(CC) $(LDFLAGS) -o $@ $(POKE_OBJS) $(LDLIBS)

$(PEEK): $(PEEK_OBJS)
	$(CC) $(LDFLAGS) -o $@ $(PEEK_OBJS) $(LDLIBS)

clean:
	-rm -f $(POKE) $(PEEK) *.elf *.gdb *.o

.PHONY: install image

# Optionally strip the final file
ifndef CONFIG_USER_DEBUG
DO_STRIP=do_strip
endif

do_strip: all
	$(STRIP) $(PEEK)

install: all $(DO_STRIP)
	$(TARGETINST) -d $(PEEK) /bin/$(PEEK)
	$(TARGETINST) -d $(POKE) /bin/$(POKE)

image: install
	make -C ${PETALINUX}/components/system image

%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<

