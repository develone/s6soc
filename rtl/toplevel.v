`timescale 10ns / 100ps
////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	toplevel.v
//
// Project:	CMod S6 System on a Chip, ZipCPU demonstration project
//
// Purpose:	This is (supposed to be) the one Xilinx specific file in the
//		project.  The idea is that all of the board specific logic,
//	the logic used in simulation, is kept in the busmaster.v  file.  It's
//	not quite true, since rxuart and txuart modules are instantiated here,
//	but it's mostly true.
//
//	One thing that makes this module unique is that all of its inputs and
//	outputs must match those on the chip, as specified within the cmod.ucf
//	file (up one directory).
//
//	Within this file you will find specific I/O for output pins, such as
//	the necessary adjustments to make an I2C port from GPIO pins, as well
//	as the clock management approach.
//
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2015-2016, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory, run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
module toplevel(i_clk_8mhz,
		o_qspi_cs_n, o_qspi_sck, io_qspi_dat,
		i_btn, o_led, o_pwm, o_pwm_shutdown_n, o_pwm_gain,
			i_uart, o_uart, o_uart_cts, i_uart_rts,
		i_kp_row, o_kp_col,
		i_gpio, o_gpio,
		io_scl, io_sda);
	input		i_clk_8mhz;
	//
	// Quad SPI Flash
	output	wire		o_qspi_cs_n;
	output	wire		o_qspi_sck;
	inout	wire	[3:0]	io_qspi_dat;
	//
	// General purpose I/O
	input		[1:0]	i_btn;
	output	wire	[3:0]	o_led;
	output	wire		o_pwm, o_pwm_shutdown_n, o_pwm_gain;
	//
	// and our serial port
	input		i_uart;
	output	wire	o_uart;
	//	and it's associated control wires
	output	wire	o_uart_cts;
	input		i_uart_rts;
	// Our keypad
	input		[3:0]	i_kp_row;
	output	wire	[3:0]	o_kp_col;
	// and our GPIO
	input		[15:2]	i_gpio;
	output	wire	[15:2]	o_gpio;
	// and our I2C port
	inout			io_scl, io_sda;


	//
	// Clock management
	//
	//	Generate a usable clock for the rest of the board to run at.
	//
	wire	ck_zero_0, clk_s;

	// Clock frequency = (20 / 2) * 8Mhz = 80 MHz
	// Clock period = 12.5 ns
	DCM_SP #(
		.CLKDV_DIVIDE(2.0),
		.CLKFX_DIVIDE(2),		// Here's the divide by two
		.CLKFX_MULTIPLY(20),		// and here's the multiply by 20
		.CLKIN_DIVIDE_BY_2("FALSE"),
		.CLKIN_PERIOD(125.0),
		.CLKOUT_PHASE_SHIFT("NONE"),
		.CLK_FEEDBACK("1X"),
		.DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"),
		.DLL_FREQUENCY_MODE("LOW"),
		.DUTY_CYCLE_CORRECTION("TRUE"),
		.PHASE_SHIFT(0),
		.STARTUP_WAIT("TRUE")
	) u0(	.CLKIN(i_clk_8mhz),
		.CLK0(ck_zero_0),
		.CLKFB(ck_zero_0),
		.CLKFX(clk_s),
		.PSEN(1'b0),
		.RST(1'b0));

	//
	// The UART serial interface
	//
	//	Perhaps this should be part of our simulation model as well.
	//	For historical reasons, internal to Gisselquist Technology,
	//	this has remained separate from the simulation, allowing the
	//	simulation to bypass whether or not these two functions work.
	//
	wire		rx_stb, tx_stb;
	wire	[7:0]	rx_data, tx_data;
	wire		tx_busy;
	wire	[29:0]	uart_setup;

	wire		reset_s;
	assign	reset_s = 1'b0;

	wire	rx_break, rx_parity_err, rx_frame_err, rx_ck_uart, tx_break;
	assign	tx_break = 1'b0;
	rxuart	rcvuart(clk_s, 1'b0, uart_setup,
			i_uart, rx_stb, rx_data,
			rx_break, rx_parity_err, rx_frame_err, rx_ck_uart);
	txuart	tcvuart(clk_s, reset_s, uart_setup, tx_break, tx_stb, tx_data,
			o_uart, tx_busy);


	//
	// BUSMASTER
	//
	//	Busmaster is so named because it contains the wishbone
	//	interconnect that all of the internal devices are hung off of.
	//	To reconfigure this device for another purpose, usually
	//	the busmaster module (i.e. the interconnect) is all that needs
	//	to be changed: either to add more devices, or to remove them.
	//
	wire	[3:0]	qspi_dat;
	wire	[1:0]	qspi_bmod;
	wire	[15:0]	w_gpio;

	busmaster	masterbus(clk_s, 1'b0,
		// External ... bus control (if enabled)
		rx_stb, rx_data, tx_stb, tx_data, tx_busy, w_uart_cts,
		// SPI/SD-card flash
		o_qspi_cs_n, o_qspi_sck, qspi_dat, io_qspi_dat, qspi_bmod,
		// Board lights and switches
		i_btn, o_led, o_pwm, { o_pwm_shutdown_n, o_pwm_gain },
		// Keypad connections
		i_kp_row, o_kp_col,
		// UART control
		uart_setup,
		// GPIO lines
		{ i_gpio, io_scl, io_sda }, w_gpio
		);
	assign	o_uart_cts = (w_uart_cts)&&(i_uart_rts);

	//
	// Quad SPI support
	//
	//	Supporting a Quad SPI port requires knowing which direction the
	//	wires are going at each instant, whether the device is in full
	//	Quad mode in, full quad mode out, or simply the normal SPI
	//	port with one wire in and one wire out.  This utilizes our
	//	control wires (qspi_bmod) to set the output lines appropriately.
	//
	assign io_qspi_dat = (~qspi_bmod[1])?({2'b11,1'bz,qspi_dat[0]})
				:((qspi_bmod[0])?(4'bzzzz):(qspi_dat[3:0]));

	//
	// I2C support
	//
	//	Supporting I2C requires a couple quick adjustments to our
	//	GPIO lines.  Specifically, we'll allow that when the output
	//	(i.e. w_gpio) pins are high, then the I2C lines float.  They
	//	will be (need to be) pulled up by a resistor in order to 
	//	match the I2C protocol, but this change makes them look/act
	//	more like GPIO pins.
	//
	assign	io_sda = (w_gpio[0]) ? 1'bz : 1'b0;
	assign	io_scl = (w_gpio[1]) ? 1'bz : 1'b0;
	assign	o_gpio[15:2] = w_gpio[15:2];

endmodule
