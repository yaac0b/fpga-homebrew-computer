import sys

from parser import Parser
from code import Code
from symbol_table import SymbolTable


class Assembler:

    def __init__(self, input_file, output_file):
        self.input_file = input_file
        self.output_file = output_file

        self.parser = Parser(input_file)
        self.code = Code()
        self.symbol_table = SymbolTable()

    def first_pass(self):
        rom_address = 0

        while self.parser.has_more_commands():
            self.parser.advance()

            if self.parser.current_command is None:
                continue

            instruction_type = self.parser.instruction_type()

            if instruction_type == "L_INSTRUCTION":
                symbol = self.parser.symbol()

                if not self.symbol_table.contains(symbol):
                    self.symbol_table.add_entry(symbol, rom_address)

            else:
                rom_address += 1

    def second_pass(self):
        # Create a new parser because the first parser
        # has already reached the end of the file.
        self.parser = Parser(self.input_file)

        next_variable_address = 16
        machine_code = []

        while self.parser.has_more_commands():
            self.parser.advance()

            if self.parser.current_command is None:
                continue

            instruction_type = self.parser.instruction_type()

            # A-instruction
            if instruction_type == "A_INSTRUCTION":
                symbol = self.parser.symbol()

                if symbol.isdigit():
                    address = int(symbol)

                else:
                    if not self.symbol_table.contains(symbol):
                        self.symbol_table.add_entry(
                            symbol,
                            next_variable_address
                        )
                        next_variable_address += 1

                    address = self.symbol_table.get_address(symbol)

                binary = format(address, "015b")
                machine_code.append("0" + binary)

            # C-instruction
            elif instruction_type == "C_INSTRUCTION":
                comp = self.code.comp(self.parser.comp())
                dest = self.code.dest(self.parser.dest())
                jump = self.code.jump(self.parser.jump())

                instruction = "111" + comp + dest + jump

                machine_code.append(instruction)

            # L-instructions generate no machine code

        with open(self.output_file, "w") as file:
            for instruction in machine_code:
                file.write(instruction + "\n")

    def assemble(self):
        self.first_pass()
        self.second_pass()


def main():
    if len(sys.argv) != 2:
        print("Usage: python assembler.py Prog.asm")
        return

    input_file = sys.argv[1]

    if input_file.endswith(".asm"):
        output_file = input_file[:-4] + ".hack"
    else:
        output_file = input_file + ".hack"

    assembler = Assembler(input_file, output_file)
    assembler.assemble()

    print(f"Assembly complete: {output_file}")


if __name__ == "__main__":
    main()