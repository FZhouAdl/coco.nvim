.PHONY: test lint fmt check

test:
	nvim --headless -u tests/minimal.lua -c 'PlenaryBustedDirectory tests/ { minimal_init = "tests/minimal.lua" }' -c qa

lint:
	selene lua/ plugin/ tests/

fmt:
	stylua lua/ plugin/ tests/

check: fmt lint test
