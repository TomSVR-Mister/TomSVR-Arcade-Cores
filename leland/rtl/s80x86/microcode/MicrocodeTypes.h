// Copyright Jamie Iles, 2017
//
// This file is part of s80x86.
//
// s80x86 is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// s80x86 is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with s80x86.  If not, see <http://www.gnu.org/licenses/>.

#pragma once

enum MC_ADriver_t {
    ADriver_RA = 0,
    ADriver_IP = 1,
    ADriver_MAR = 2,
    ADriver_MDR = 3
};

enum MC_BDriver_t {
    BDriver_RB = 0,
    BDriver_IMMEDIATE = 1,
    BDriver_SR = 2,
    BDriver_TEMP = 3,
    BDriver_IMMEDIATE2 = 4
};

enum MC_ALUOp_t {
    ALUOp_SELA = 0,
    ALUOp_SELB = 1,
    ALUOp_ADD = 2,
    ALUOp_ADC = 3,
    ALUOp_AND = 4,
    ALUOp_XOR = 5,
    ALUOp_OR = 6,
    ALUOp_SUB = 7,
    ALUOp_SUBREV = 8,
    ALUOp_SBB = 9,
    ALUOp_SBBREV = 10,
    ALUOp_GETFLAGS = 11,
    ALUOp_SETFLAGSB = 12,
    ALUOp_SETFLAGSA = 13,
    ALUOp_CMC = 14,
    ALUOp_SHR = 15,
    ALUOp_SHL = 16,
    ALUOp_SAR = 17,
    ALUOp_ROR = 18,
    ALUOp_ROL = 19,
    ALUOp_RCL = 20,
    ALUOp_RCR = 21,
    ALUOp_NOT = 22,
    ALUOp_NEXT = 23,
    ALUOp_AAA = 24,
    ALUOp_AAS = 25,
    ALUOp_DAA = 26,
    ALUOp_DAS = 27,
    ALUOp_MUL = 28,
    ALUOp_IMUL = 29,
    ALUOp_DIV = 30,
    ALUOp_IDIV = 31,
    ALUOp_EXTEND = 32,
    ALUOp_BOUNDL = 33,
    ALUOp_BOUNDH = 34,
    ALUOp_ENTER_FRAME_TEMP_ADDR = 35
};

enum MC_JumpType_t {
    JumpType_UNCONDITIONAL = 0,
    JumpType_RM_REG_MEM = 1,
    JumpType_OPCODE = 2,
    JumpType_DISPATCH_REG = 3,
    JumpType_HAS_NO_REP_PREFIX = 4,
    JumpType_ZERO = 5,
    JumpType_REP_NOT_COMPLETE = 6,
    JumpType_JUMP_TAKEN = 7,
    JumpType_RB_ZERO = 8,
    JumpType_LOOP_DONE = 9
};

enum MC_RDSelSource_t {
    RDSelSource_NONE = 0,
    RDSelSource_MODRM_REG = 1,
    RDSelSource_MODRM_RM_REG = 2,
    RDSelSource_MICROCODE_RD_SEL = 3
};

enum MC_MARWrSel_t {
    MARWrSel_EA = 0,
    MARWrSel_Q = 1
};

enum MC_TEMPWrSel_t {
    TEMPWrSel_Q_LOW = 0,
    TEMPWrSel_Q_HIGH = 1
};

enum MC_UpdateFlags_t {
    UpdateFlags_CF = 0,
    UpdateFlags_PF = 1,
    UpdateFlags_AF = 2,
    UpdateFlags_ZF = 3,
    UpdateFlags_SF = 4,
    UpdateFlags_TF = 5,
    UpdateFlags_IF = 6,
    UpdateFlags_DF = 7,
    UpdateFlags_OF = 8
};

enum MC_RegWrSource_t {
    RegWrSource_Q = 0,
    RegWrSource_QUOTIENT = 1,
    RegWrSource_REMAINDER = 2
};

enum MC_WidthType_t {
    WidthType_W16 = 0,
    WidthType_W8 = 1,
    WidthType_WAUTO = 2
};

