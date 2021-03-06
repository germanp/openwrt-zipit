/*
 *  Startup Code for MIPS32 XBURST CPU-core
 *
 *  Copyright (c) 2010 Xiangfu Liu <xiangfu@sharism.cc>
 *
 * See file CREDITS for list of people who contributed to this
 * project.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */

#include <config.h>
#include <version.h>
#include <asm/regdef.h>
#include <asm/mipsregs.h>
#include <asm/addrspace.h>
#include <asm/cacheops.h>

#include <asm/jz4740.h>

	.set noreorder

	.globl _start
	.text
_start:
	/* Initialize GOT pointer.
	*/
	bal     1f
	nop
	.word   _GLOBAL_OFFSET_TABLE_
1:
	move    gp, ra
	lw      t1, 0(ra)
	move	gp, t1

	li	t0, CONFIG_SYS_SDRAM_BASE + CONFIG_SYS_INIT_SP_OFFSET
	la	sp, 0(t0)

	la	t9, board_init_f
	j	t9
	nop

/*
 * void relocate_code (addr_sp, gd, addr_moni)
 *
 * This "function" does not return, instead it continues in RAM
 * after relocating the monitor code.
 *
 * a0 = addr_sp
 * a1 = gd
 * a2 = destination address
 */
	.globl	relocate_code
	.ent	relocate_code
relocate_code:
	move	sp, a0		/* Set new stack pointer	*/

	li	t0, TEXT_BASE
	la	t3, in_ram
	lw	t2, -12(t3)	/* t2 <-- uboot_end_data	*/
	move	t1, a2

	/*
	 * Fix GOT pointer:
	 *
	 * New GOT-PTR = (old GOT-PTR - TEXT_BASE) + Destination Address
	 */
	move	t6, gp
	sub	gp, TEXT_BASE
	add	gp, a2			/* gp now adjusted	*/
	sub	t6, gp, t6		/* t6 <-- relocation offset*/

	/*
	 * t0 = source address
	 * t1 = target address
	 * t2 = source end address
	 */
1:
	lw	t3, 0(t0)
	sw	t3, 0(t1)
	addu	t0, 4
	ble	t0, t2, 1b
	addu	t1, 4			/* delay slot		*/

	/* If caches were enabled, we would have to flush them here.
	 * flush d-cache */
	.set	mips32
	li	t0, KSEG0
	addi	t1, t0, CONFIG_SYS_DCACHE_SIZE
2:
	cache	Index_Writeback_Inv_D, 0(t0)
	bne	t0, t1, 2b
	addi	t0, CONFIG_SYS_CACHELINE_SIZE

	sync

	/* flush i-cache */
	li	t0, KSEG0
	addi	t1, t0, CONFIG_SYS_ICACHE_SIZE
3:
	cache	Index_Invalidate_I, 0(t0)
	bne	t0, t1, 3b
	addi	t0, CONFIG_SYS_CACHELINE_SIZE

	/* Invalidate BTB */
	mfc0	t0, CP0_CONFIG, 7
	nop
	ori	t0, 2
	mtc0	t0, CP0_CONFIG, 7
	nop

	.set	mips0

	/* Jump to where we've relocated ourselves.
	 */
	addi	t0, a2, in_ram - _start
	j	t0
	nop

	.word	uboot_end_data
	.word	uboot_end
	.word	num_got_entries

in_ram:
	/* Now we want to update GOT  */
	lw	t3, -4(t0)	/* t3 <-- num_got_entries	*/
	addi	t4, gp, 8	/* Skipping first two entries.	*/
	li	t2, 2
1:
	lw	t1, 0(t4)
	beqz	t1, 2f
	add	t1, t6
	sw	t1, 0(t4)
2:
	addi	t2, 1
	blt	t2, t3, 1b
	addi	t4, 4		/* delay slot			*/

	/* Clear BSS  */
	lw	t1, -12(t0)	/* t1 <-- uboot_end_data	*/
	lw	t2, -8(t0)	/* t2 <-- uboot_end		*/
	add	t1, t6		/* adjust pointers		*/
	add	t2, t6

	sub	t1, 4
1:	addi	t1, 4
	bltl	t1, t2, 1b
	sw	zero, 0(t1)	/* delay slot			*/

	move	a0, a1
	la	t9, board_init_r
	j	t9
	move	a1, a2		/* delay slot			*/

	.end	relocate_code
	