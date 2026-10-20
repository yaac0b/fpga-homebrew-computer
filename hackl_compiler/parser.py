class Parser:
    def __init__(self, filename):
        with open(filename, "r") as file:
            self.lines = file.readlines()

        self.current_command = None
        self.current_line = 0
    def has_more_commands(self):
        return self.current_line < len(self.lines) 

    def advance(self):
        while self.has_more_commands():
            line = self.lines[self.current_line]
            self.current_line += 1

            line = line.split("//")[0].strip()

            if line:
                self.current_command = line
                return   
    def instruction_type(self):
        if self.current_command.startswith("@"):
            return "A_INSTRUCTION"

        elif self.current_command.startswith("("):
            return "L_INSTRUCTION"

        else:
            return "C_INSTRUCTION"

    def symbol(self):
        if self.current_command.startswith("@"):
            return self.current_command[1:]

        elif self.current_command.startswith("("):
            return self.current_command[1:-1]    

    def dest(self):
        if "=" in self.current_command:
            return self.current_command.split("=")[0].strip()

        return None


    def comp(self):
        command = self.current_command

        if "=" in command:
            command = command.split("=")[1]

        if ";" in command:
            command = command.split(";")[0]

        return command.strip()


    def jump(self):
        if ";" in self.current_command:
            return self.current_command.split(";")[1].strip()

        return None


# parser = Parser("Prog.asm")

# while parser.has_more_commands():
#     parser.advance()

#     if parser.current_command:
#         print(
#             parser.current_command,
#             "-> dest:", parser.dest(),
#             "comp:", parser.comp(),
#             "jump:", parser.jump()
#         )