CXX ?= g++
AS := nasm
LD ?= ld
GRUB_MKRESCUE ?= $(shell command -v grub2-mkrescue 2>/dev/null || command -v grub-mkrescue 2>/dev/null || echo grub-mkrescue)
VBOXMANAGE ?= VBoxManage
VM_NAME ?= KyronOS
EFI ?= off
VBOX_FIRMWARE := bios
ifeq ($(EFI),on)
VBOX_FIRMWARE := efi
endif
CXXFLAGS := -m32 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-pic -Wall -Wextra -Werror -Iinclude
LDFLAGS := -m elf_i386 -T boot/linker.ld
BUILD := build

.PHONY: all kernel iso run debug clean test
all: kernel

kernel: $(BUILD)/kyronos.kernel

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/entry.o: boot/entry.asm | $(BUILD)
	$(AS) -f elf32 $< -o $@

$(BUILD)/console.o: src/kernel/console.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD)/keyboard.o: src/kernel/keyboard.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD)/usb_keyboard.o: src/drivers/usb_keyboard.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD)/shell.o: src/kernel/shell.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD)/kernel.o: src/kernel/kernel.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD)/kyronos.kernel: $(BUILD)/entry.o $(BUILD)/console.o $(BUILD)/keyboard.o $(BUILD)/usb_keyboard.o $(BUILD)/shell.o $(BUILD)/kernel.o
	$(LD) $(LDFLAGS) -o $@ $^

iso: kernel
	command -v "$(GRUB_MKRESCUE)" >/dev/null || { echo 'Missing GRUB rescue tool. See docs/BUILDING.md.'; exit 1; }
	mkdir -p $(BUILD)/iso/boot/grub
	cp $(BUILD)/kyronos.kernel $(BUILD)/iso/boot/kyronos.kernel
	cp boot/grub.cfg $(BUILD)/iso/boot/grub/grub.cfg
	$(GRUB_MKRESCUE) -o $(BUILD)/kyronos.iso $(BUILD)/iso

run: iso
	$(VBOXMANAGE) showvminfo "$(VM_NAME)" >/dev/null 2>&1 || $(VBOXMANAGE) createvm --name "$(VM_NAME)" --register
	$(VBOXMANAGE) modifyvm "$(VM_NAME)" --firmware $(VBOX_FIRMWARE) --memory 128 --boot1 dvd --boot2 none --nic1 nat
	$(VBOXMANAGE) storagectl "$(VM_NAME)" --name KyronOSStorage --add ide --controller PIIX4 >/dev/null 2>&1 || true
	$(VBOXMANAGE) storageattach "$(VM_NAME)" --storagectl KyronOSStorage --port 0 --device 0 --type dvddrive --medium "$(abspath $(BUILD)/kyronos.iso)"
	$(VBOXMANAGE) startvm "$(VM_NAME)" --type gui

debug: iso
	@echo "VirtualBox debugging requires a configured VirtualBox debug provider."
	@echo "The ISO is ready at $(BUILD)/kyronos.iso."

test:
	$(MAKE) -C tests
	./tests/ksfs_tests

clean:
	rm -rf $(BUILD) tests/*.o tests/ksfs_tests
