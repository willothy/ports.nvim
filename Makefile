TESTS_DIR := tests
PLENARY := .tests/plenary.nvim

.PHONY: test lint format clean

# Run the plenary/busted test suite headlessly.
test: $(PLENARY)
	PLENARY_PATH=$(PLENARY) nvim --headless --noplugin -u $(TESTS_DIR)/minimal_init.lua \
		-c "PlenaryBustedDirectory $(TESTS_DIR)/ { minimal_init = '$(TESTS_DIR)/minimal_init.lua', sequential = true }"

# Check formatting and run the linter.
lint:
	stylua --check lua/ plugin/ ftplugin/ tests/
	luacheck lua/ plugin/ ftplugin/

# Apply formatting.
format:
	stylua lua/ plugin/ ftplugin/ tests/

$(PLENARY):
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY)

clean:
	rm -rf .tests
