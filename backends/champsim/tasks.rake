file "#{$root}/gen/champsim/riscv.h" => "#{$root}/.stamps/arch-gen-champsim.stamp" do |t|
  arch_def = arch_def_for("champsim")

  File.open t.name, "w" do |file|
    file.write <<~CC
      #include <cstdint>
      #include <optional>

      #include "ir2.h"

      namespace champsim::riscv {

      static inline bool link(uint8_t r) {
        return r == 1 || r == 5;
      }

      struct decoded_inst {
      decoded_inst(uint32_t inst) {
    CC

    arch_def.implemented_instructions.each do |instruction|
      name = instruction.name
      encoding = instruction.encoding(64)
      decode_variables = encoding.decode_variables
      mask = encoding.format.gsub("0", "1").gsub("-", "0")
      match = encoding.format.gsub("-", "0")

      file.write "if ((inst & 0b#{mask}) == 0b#{match}) {\n"

      imm = decode_variables.find { _1.name == "imm" }

      unless imm.nil?
        offset = imm.size

        bits = imm.bits.each_with_index.map do |b, index|
          b = b..b if b.is_a?(Integer)
          offset -= b.size
          left = 31 - b.max
          right = left + b.min

          if index == 0 && !%W[csrrci csrrsi csrrwi fsflagsi fsrmi].include?(name)
            "((static_cast<int32_t>(inst) << #{left}) >> #{right}) << #{offset}"
          else
            "((inst << #{left}) >> #{right}) << #{offset}"
          end
        end

        file.write "imm = #{bits.join(" | ")};\n"
      end

      [["source", 3], ["destination", 1]].each do |name, size|
        registers = decode_variables.select do |variable|
          variable.name[1] == name[0] && "fr".include?(variable.name[0])
        end

        raise "too many #{name} registers" if registers.size > size
        registers.sort_by!(&:name)

        registers.each_with_index do |register, index|
          offset = register.size

          bits = register.bits.map do |b|
            b = b..b if b.is_a?(Integer)
            offset -= b.size
            left = 31 - b.max
            right = left + b.min

            "((inst << #{left}) >> #{right}) << #{offset}"
          end

          file.write "#{name}_registers[#{index}] = (#{bits.join(" | ")})"
          file.write " + 32" if register.name[0] == "f"
          file.write ";\n"
        end

        if registers.size < size
          file.write "#{name}_registers[#{registers.size}] = UINT8_MAX;\n"
        end
      end

      case name
      when 'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu'
        file.write "branch_type = BRANCH_CONDITIONAL;\n"
      when 'jal'
        file.write <<~CC
          branch_type = link(destination_registers[0]) ?
                        BRANCH_DIRECT_CALL : BRANCH_DIRECT_JUMP;
        CC
      when 'jalr'
        file.write <<~CC
          if (link(destination_registers[0])) {
            branch_type = link(source_registers[0]) &&
                          source_registers[0] == destination_registers[0] ?
                          BRANCH_YIELD : BRANCH_INDIRECT_CALL;
          } else {
            branch_type = link(source_registers[0]) ? BRANCH_RETURN : BRANCH_INDIRECT;
          }
        CC
      else
        file.write "branch_type = NOT_BRANCH;\n"
      end

      case name
      when 'add'
        op = 'LISA_ADD_D'
      when 'addi'
        op = 'LISA_ADDI_D'
      when 'addiw'
        op = 'LISA_ADDI_W'
      when 'addw'
        op = 'LISA_ADD_W'
      when 'and'
        op = 'LISA_AND'
      when 'andi'
        op = 'LISA_ANDI'
      when 'fld'
        op = 'LISA_FLD_D'
      when 'flw'
        op = 'LISA_FLD_S'
      when 'lb'
        op = 'LISA_LD_B'
      when 'lbu'
        op = 'LISA_LD_BU'
      when 'ld'
        op = 'LISA_LD_D'
      when 'lh'
        op = 'LISA_LD_H'
      when 'lhu'
        op = 'LISA_LD_HU'
      when 'lr_w'
        op = 'LISA_LL_W'
      when 'lr_d'
        op = 'LISA_LL_D'
      when 'lw'
        op = 'LISA_LD_W'
      when 'lwu'
        op = 'LISA_LD_WU'
      when 'mul', 'mulh', 'mulhsu', 'mulhu'
        op = 'LISA_MUL_W'
      when 'or', 'ori'
        op = 'LISA_OR'
      when 'sll', 'slli'
        op = 'LISA_SLLI_D'
      when 'sllw', 'slliw'
        op = 'LISA_SLLI_W'
      when 'sra'
        op = 'LISA_SRA_D'
      when 'srai'
        op = 'LISA_SRAI_D'
      when 'sraiw'
        op = 'LISA_SRAI_W'
      when 'sraw'
        op = 'LISA_SRA_W'
      when 'srl'
        op = 'LISA_SRL_D'
      when 'srli'
        op = 'LISA_SRLI_D'
      when 'srliw'
        op = 'LISA_SRLI_W'
      when 'srlw'
        op = 'LISA_SRL_W'
      when 'sub'
        op = 'LISA_SUB_D'
      when 'subw'
        op = 'LISA_SUB_W'
      when 'xor'
        op = 'LISA_XOR'
      when 'xori'
        op = 'LISA_XORI'
      else
        op = 'LISA_INVALID'
      end

      case name
      when 'lb', 'lbu', 'sb'
        ls_size = 1
      when 'lh', 'lhu', 'sh'
        ls_size = 2
      when 'amoadd.w', 'amoand.w', 'amomax.w', 'amomaxu.w', 'amomin.w', 'amominu.w', 'amoor.w', 'amoswap.w', 'amoxor.w',
           'flw', 'fsw', 'lw', 'lw', 'lwu', 'lr.w', 'sc.w', 'sw'
        ls_size = 4
      when 'amoadd.d', 'amoand.d', 'amomax.d', 'amomaxu.d', 'amomin.d', 'amominu.d', 'amoor.d', 'amoswap.d', 'amoxor.d',
           'fld', 'fsd', 'ld', 'sd', 'lr.d', 'sc.d'
        ls_size = 8
      else
        ls_size = 0
      end

      file.write <<~CC
        op = #{op};
        ls_size = #{ls_size};
        unsign_ext = #{%W[lbu lhu lwu].include?(name)};
        } else
      CC
    end

    file.write <<~CC
      {
      op = LISA_INVALID;
      source_registers[0] = UINT8_MAX;
      destination_registers[0] = UINT8_MAX;
      branch_type = NOT_BRANCH;
      ls_size = 0;
      unsign_ext = false;
      }
      }

      IR2_OPCODE op;
      std::optional<uint32_t> imm;
      uint8_t source_registers[3];
      uint8_t destination_registers[1];
      uint8_t branch_type;
      uint8_t ls_size;
      bool unsign_ext;
      };

      }
    CC
  end
end
