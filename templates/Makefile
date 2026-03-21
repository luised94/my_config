# ============================================================
# Makefile — C Project Template
# ============================================================

CC      = gcc
STD     = -std=c99

CFLAGS  = $(STD) -Wall -Wextra -Werror -g -O0 \
          -fsanitize=address,undefined \
          -fno-omit-frame-pointer

TARGET  = main
SRC     = main.c

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)

asm: $(SRC)
	$(CC) $(CFLAGS) -S -o $(TARGET).s $(SRC)

.PHONY: run clean asm
