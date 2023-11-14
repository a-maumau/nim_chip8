CC         = nim c
CFLAGS     =
TARGET     = chip8
SRC        = main.nim
# these are for just watching when they are updated
REQUISITES = *.nim

$(TARGET): $(SRC) $(REQUISITES)
	$(CC) -d:release --opt:speed -o=$@ $(SRC)

all: clean $(TARGET) run

run:
	-./$(TARGET)

clean:
	-rm $(TARGET) 
