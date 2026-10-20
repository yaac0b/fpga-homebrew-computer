class SymbolTable:
    def __init__(self):
        self.symbols = {}

        for i in range(16):
            self.symbols[f"R{i}"] = i

        self.symbols["SP"] = 0
        self.symbols["LCL"] = 1
        self.symbols["ARG"] = 2
        self.symbols["THIS"] = 3
        self.symbols["THAT"] = 4

        self.symbols["SCREEN"] = 16384
        self.symbols["KBD"] = 24576

    def add_entry(self, symbol, address):
        self.symbols[symbol] = address

    def contains(self, symbol):
        return symbol in self.symbols

    def get_address(self, symbol):
        return self.symbols[symbol]
    
# table = SymbolTable()

# print(table.get_address("R0"))
# print(table.get_address("R15"))
# print(table.get_address("SCREEN"))

# table.add_entry("LOOP", 10)

# print(table.contains("LOOP"))
# print(table.get_address("LOOP"))    