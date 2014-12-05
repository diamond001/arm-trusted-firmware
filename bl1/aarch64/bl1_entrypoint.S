/*
 * Copyright (c) 2013-2014, ARM Limited and Contributors. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * Redistributions of source code must retain the above copyright notice, this
 * list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * Neither the name of ARM nor the names of its contributors may be used
 * to endorse or promote products derived from this software without specific
 * prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <arch.h>
#include <asm_macros.S>

	.globl	bl1_entrypoint


	/* -----------------------------------------------------
	 * bl1_entrypoint() is the entry point into the trusted
	 * 热重启或者冷重启的时候，可信固件的入口点
	 * firmware code when a cpu is released from warm or
	 * cold reset.
	 * -----------------------------------------------------
	 */

func bl1_entrypoint
	/* ---------------------------------------------
	 * Set the CPU endianness before doing anything
	 * that might involve memory reads or writes.
	 * 在做任何内存相关的读或者写之前，设置CPU的大小端
	 * ---------------------------------------------
	 */
         /* sctlr_el3 Provides top level control of the system, 
	    including its memory system, at EL3 */
	mrs	x0, sctlr_el3
	bic	x0, x0, #SCTLR_EE_BIT  //给x0的第25位清零...
	msr	sctlr_el3, x0 // 设置为小端模式... 
	isb    //内存屏障指令，等待所有流水线中的指令执行完毕

	/* ---------------------------------------------
	 * Perform any processor specific actions upon
	 * reset e.g. cache, tlb invalidations etc.
   	 * 复位时，做任何处理器相关的初始化动作
         * 例如，cache，tlb失效等等...
	 * ---------------------------------------------
	 */
	bl	reset_handler

	/* ---------------------------------------------
	 * Enable the instruction cache, stack pointer
	 * and data access alignment checks
         * 使能指令缓存，栈指针，数据访问对齐检查...
	 * ---------------------------------------------
	 */
	mov	x1, #(SCTLR_I_BIT | SCTLR_A_BIT | SCTLR_SA_BIT)
	mrs	x0, sctlr_el3
	orr	x0, x0, x1
	msr	sctlr_el3, x0
	isb

	/* ---------------------------------------------
	 * Set the exception vector to something sane.
         * 设置异常向量
	 * ---------------------------------------------
	 */
	adr	x0, bl1_exceptions  /* 把bl1_exceptions所对应的地址给x0 */
	msr	vbar_el3, x0    /* Vector Base Address Register (EL3) */
	isb   

	/* ---------------------------------------------
	 * Enable the SError interrupt now that the
	 * exception vectors have been setup.
         * 既然异常向量已经设置好，使能SError中断
	 * ---------------------------------------------
	 */
	msr	daifclr, #DAIF_ABT_BIT

	/* ---------------------------------------------------------------------
	 * The initial state of the Architectural feature trap register
	 * (CPTR_EL3) is unknown and it must be set to a known state. 
	 * 体系结构的初始状态特征陷入寄存器（CPTR_EL3）未知的，注意，它必须设置为已知状态
         * All feature traps are disabled. Some bits in this register are marked as
	 * Reserved and should not be modified.
	 * 所有特征陷入是禁止的。这个寄存器中的一些位被标记为保留并且不能被修改。
	 * CPTR_EL3.TCPAC: This causes a direct access to the CPACR_EL1 from EL1
	 *  or the CPTR_EL2 from EL2 to trap to EL3 unless it is trapped at EL2.
           除非陷入EL2，否则它导致从EL1对CPACR_EL1的访问或者从EL2对CPTR_EL2的访问来达到陷入EL3的目的...

	 * CPTR_EL3.TTA: This causes access to the Trace functionality to trap
	 *  to EL3 when executed from EL0, EL1, EL2, or EL3. If system register
	 *  access to trace functionality is not supported, this bit is RES0.
	    当从EL0....执行的时候，这导致对trace功能的访问以陷入到EL3。如果系统寄存器
            对跟踪功能的访问不被支持，那么这个bit为RES0
	 * CPTR_EL3.TFP: This causes instructions that access the registers
	 *  associated with Floating Point and Advanced SIMD execution to trap
	 *  to EL3 when executed from any exception level, unless trapped to EL1
	 *  or EL2.
            这个导致访问寄存器的指令和浮点数组织起来，高级的SIMD执行陷入EL3当从任何异等级陷入EL3
            除非陷入到EL1或者EL2
	 * ---------------------------------------------------------------------
	 */
	mrs	x0, cptr_el3
	bic	w0, w0, #TCPAC_BIT
	bic	w0, w0, #TTA_BIT
	bic	w0, w0, #TFP_BIT
	msr	cptr_el3, x0

	/* -------------------------------------------------------
	 * Will not return from this macro if it is a warm boot.
	 * 
	 * -------------------------------------------------------
	 */
	wait_for_entrypoint

	bl	platform_mem_init

	/* ---------------------------------------------
	 * Init C runtime environment.
	 *   - Zero-initialise the NOBITS sections.
	 *     There are 2 of them:
	 *       - the .bss section;
	 *       - the coherent memory section.
	 *   - Copy the data section from BL1 image
	 *     (stored in ROM) to the correct location
	 *     in RAM.
	 * ---------------------------------------------
	 */
	ldr	x0, =__BSS_START__
	ldr	x1, =__BSS_SIZE__
	bl	zeromem16

	ldr	x0, =__COHERENT_RAM_START__
	ldr	x1, =__COHERENT_RAM_UNALIGNED_SIZE__
	bl	zeromem16

	ldr	x0, =__DATA_RAM_START__
	ldr	x1, =__DATA_ROM_START__
	ldr	x2, =__DATA_SIZE__
	bl	memcpy16

	/* --------------------------------------------
	 * Allocate a stack whose memory will be marked
	 * as Normal-IS-WBWA when the MMU is enabled.
	 * There is no risk of reading stale stack
	 * memory after enabling the MMU as only the
	 * primary cpu is running at the moment.
	 * --------------------------------------------
	 */
	mrs	x0, mpidr_el1
	bl	platform_set_stack

	/* ---------------------------------------------
	 * Architectural init. can be generic e.g.
	 * enabling stack alignment and platform spec-
	 * ific e.g. MMU & page table setup as per the
	 * platform memory map. Perform the latter here
	 * and the former in bl1_main.
	 * ---------------------------------------------
	 */
	bl	bl1_early_platform_setup
	bl	bl1_plat_arch_setup

	/* --------------------------------------------------
	 * Initialize platform and jump to our c-entry point
	 * for this type of reset. Panic if it returns
	 * --------------------------------------------------
	 */
	bl	bl1_main
panic:
	b	panic
