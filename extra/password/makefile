
OBJECTS = nshsrvpw.o

# CC defines the compiler.
CC = g++

# Set CCOPTS - the compiler options.
CCOPTS = -c -m64

# set NOTESDIR to specify where to search for the Notes library file
NOTESDIR = $(Notes_ExecDirectory)

# -o $(TARGET) causes compiler to create target rather than a.out
LINKOPTS = -shared -fpic -Wl,-R$(NOTESDIR),-ztext

# Notes API header files require UNIX to be defined.
DEFINES = -DGCC3 -DGCC4 -fno-strict-aliasing -DGCC_LBLB_NOT_SUPPORTED  -DUNIX -DLINUX -DLINUX86 -DND64 -DLINUX64 -DW -DLINUX86_64 -DDTRACE -DPTHREAD_KERNEL -D_REENTRANT -DUSE_THREADSAFE_INTERFACES -D_POSIX_THREAD_SAFE_FUNCTIONS  -DHANDLE_IS_32BITS -DHAS_IOCP -DHAS_BOOL -DHAS_DLOPEN -DUSE_PTHREAD_INTERFACES -DLARGE64_FILES -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -DNDUNIX64 -DLONGIS64BIT   -DPRODUCTION_VERSION -DOVERRIDEDEBUG  -fPIC -Wno-write-strings

# set INCDIR to specify where to search for include files
INCDIR = $(LOTUS)/notesapi/include

# set LIBS to list all the libraries ld should link with.
LIBS = -lnotes -lm -lpthread -lc -lresolv -ldl

libnshsrvpw.so: nshsrvpw.o
	$(CC) $(LINKOPTS) nshsrvpw.o -L$(NOTESDIR) -Wl,-rpath-link $(NOTESDIR) $(LIBS) -o libnshsrvpw.so

nshspw: nshpw.o
	$(CC) $(LINKOPTS) nshpw.o -o nshpw 

nshsrvpw.o: nshsrvpw.cpp
	$(CC) $(CCOPTS) $(DEFINES) -I$(INCDIR) nshsrvpw.cpp 

nshpw.o: nshpw.cpp
	$(CC) $(CCOPTS) nshpw.cpp 

all: libnshsrvpw.so nshpw perm

clean:
	rm -rf libnshsrvpw.so nshpw nshsrvpw.o nshpw.o

perm:
	chown vault:vault nshpw
	chmod u+s nshpw
