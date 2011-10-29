`include "timescale.v"

module pipeline(
	input				clk,
	output [31:0] 		iaddress_o,
	input [31:0]		idata_i,
	output 				iaccess_o,
	output [31:0] 		daddress_o,
	output 				daccess_o,
	input				dcache_hit_i,
	output 				dwrite_o,
	output [3:0] 		dsel_o,
	output [31:0] 		ddata_o,
	input [31:0] 		ddata_i);
	
	wire[31:0]			if_instruction;
	wire[31:0]			ss_instruction;
	wire[31:0]			dc_instruction;
	wire[31:0]			ex_instruction;
	wire[31:0]			ma_instruction;
	wire[4:0]			scalar_sel1;
	wire[4:0]			scalar_sel2;
	wire[4:0]			vector_sel1;
	wire[4:0]			vector_sel2;
	wire[31:0]			scalar_value1;
	wire[31:0]			scalar_value2;
	wire[511:0]			vector_value1;
	wire[511:0]			vector_value2;
	wire[31:0]			immediate_value;
	wire[2:0]			mask_src;
	wire				op1_is_vector;
	wire[1:0]			op2_src;
	wire 				store_value_is_vector;
	wire[31:0]			ex_store_value;
	wire	 			ds_has_writeback;
	wire[4:0]			ds_writeback_reg;
	wire				ds_writeback_is_vector;
	wire	 			ex_has_writeback;
	wire[4:0]			ex_writeback_reg;
	wire				ex_writeback_is_vector;
	wire	 			ma_has_writeback;
	wire[4:0]			ma_writeback_reg;
	wire				ma_writeback_is_vector;
	wire[4:0]			wb_writeback_reg;
	wire[511:0]			wb_writeback_value;
	wire[15:0]			wb_writeback_mask;
	wire				wb_writeback_is_vector;
	wire[15:0]			ex_mask;
	wire[15:0]			ma_mask;
	wire[511:0]			ex_result;
	wire[511:0]			ma_result;
	wire[5:0]			alu_op;
	wire				enable_scalar_reg_store;
	wire				enable_vector_reg_store;
	wire [3:0]			ss_lane_select;
	wire [3:0]			ds_lane_select;
	wire [3:0]			ex_lane_select;
	wire [3:0]			ma_lane_select;
	reg[4:0] 			vector_sel1_l;
	reg[4:0] 			vector_sel2_l;
	reg[4:0] 			scalar_sel1_l;
	reg[4:0] 			scalar_sel2_l;
	wire[31:0]			if_pc;
	wire[31:0]			ss_pc;
	wire[31:0]			ds_pc;
	wire[31:0]			ex_pc;
	wire[31:0]			ma_pc;
	wire				ex_rollback_request;
	wire[31:0]			ex_rollback_address;
	wire				flush_request;
	wire				restart_request;
	wire[31:0]			restart_address;
	
	rollback_controller rbc(
		.clk(clk),
		.rollback_request_i(ex_rollback_request),
		.rollback_address_i(ex_rollback_address),
		.flush_request_o(flush_request),
		.restart_request_o(restart_request),
		.restart_address_o(restart_address));
	
	instruction_fetch_stage ifs(
		.clk(clk),
		.pc_o(if_pc),
		.iaddress_o(iaddress_o),
		.idata_i(idata_i),
		.iaccess_o(iaccess_o),
		.instruction_o(if_instruction),
		.restart_request_i(restart_request),
		.restart_address_i(restart_address));

	strand_select_stage ss(
		.clk(clk),
		.pc_i(if_pc),
		.pc_o(ss_pc),
		.lane_select_o(ss_lane_select),
		.instruction_i(if_instruction),
		.instruction_o(ss_instruction),
		.flush_i(flush_request));

	decode_stage ds(
		.clk(clk),
		.instruction_i(ss_instruction),
		.instruction_o(dc_instruction),
		.pc_i(ss_pc),
		.pc_o(ds_pc),
		.lane_select_i(ss_lane_select),
		.lane_select_o(ds_lane_select),
		.immediate_o(immediate_value),
		.mask_src_o(mask_src),
		.op1_is_vector_o(op1_is_vector),
		.op2_src_o(op2_src),
		.store_value_is_vector_o(store_value_is_vector),
		.scalar_sel1_o(scalar_sel1),
		.scalar_sel2_o(scalar_sel2),
		.vector_sel1_o(vector_sel1),
		.vector_sel2_o(vector_sel2),
		.has_writeback_o(ds_has_writeback),
		.writeback_reg_o(ds_writeback_reg),
		.writeback_is_vector_o(ds_writeback_is_vector),
		.alu_op_o(alu_op),
		.flush_i(flush_request));

	assign enable_scalar_reg_store = wb_has_writeback && ~wb_writeback_is_vector;
	assign enable_vector_reg_store = wb_has_writeback && wb_writeback_is_vector;

	scalar_register_file srf(
		.clk(clk),
		.sel1_i(scalar_sel1),
		.sel2_i(scalar_sel2),
		.value1_o(scalar_value1),
		.value2_o(scalar_value2),
		.write_reg_i(wb_writeback_reg),
		.write_value_i(wb_writeback_value[31:0]),
		.write_enable_i(enable_scalar_reg_store));
	
	vector_register_file vrf(
		.clk(clk),
		.sel1_i(vector_sel1),
		.sel2_i(vector_sel2),
		.value1_o(vector_value1),
		.value2_o(vector_value2),
		.write_reg_i(wb_writeback_reg),
		.write_value_i(wb_writeback_value),
		.write_mask_i(wb_writeback_mask),
		.write_en_i(enable_vector_reg_store));
	
	always @(posedge clk)
	begin
		vector_sel1_l <= vector_sel1;
		vector_sel2_l <= vector_sel2;
		scalar_sel1_l <= scalar_sel1;
		scalar_sel2_l <= scalar_sel2;
	end
	
	execute_stage exs(
		.clk(clk),
		.instruction_i(dc_instruction),
		.instruction_o(ex_instruction),
		.pc_i(ds_pc),
		.pc_o(ex_pc),
		.lane_select_i(ds_lane_select),
		.lane_select_o(ex_lane_select),
		.mask_src_i(mask_src),
		.op1_is_vector_i(op1_is_vector),
		.op2_src_i(op2_src),
		.scalar_value1_i(scalar_value1),
		.scalar_value2_i(scalar_value2),
		.vector_value1_i(vector_value1),
		.vector_value2_i(vector_value2),
		.scalar_sel1_i(scalar_sel1_l),
		.scalar_sel2_i(scalar_sel2_l),
		.vector_sel1_i(vector_sel1_l),
		.vector_sel2_i(vector_sel2_l),
		.immediate_i(immediate_value),
		.store_value_is_vector_i(store_value_is_vector),
		.store_value_o(ex_store_value),
		.has_writeback_i(ds_has_writeback),
		.writeback_reg_i(ds_writeback_reg),
		.writeback_is_vector_i(ds_writeback_is_vector),
		.has_writeback_o(ex_has_writeback),
		.writeback_reg_o(ex_writeback_reg),
		.writeback_is_vector_o(ex_writeback_is_vector),
		.mask_o(ex_mask),
		.result_o(ex_result),
		.alu_op_i(alu_op),
		.daddress_o(daddress_o),
		.daccess_o(daccess_o),
		.bypass1_register(ma_writeback_reg),	
		.bypass1_has_writeback(ma_has_writeback),
		.bypass1_is_vector(ma_writeback_is_vector),
		.bypass1_value(ma_result),
		.bypass1_mask(ma_mask),
		.bypass2_register(wb_writeback_reg),	
		.bypass2_has_writeback(wb_has_writeback),
		.bypass2_is_vector(wb_writeback_is_vector),
		.bypass2_value(wb_writeback_value),
		.bypass2_mask(wb_writeback_mask),
		.rollback_request_o(ex_rollback_request),
		.rollback_address_o(ex_rollback_address));

	memory_access_stage mas(
		.clk(clk),
		.instruction_i(ex_instruction),
		.instruction_o(ma_instruction),
		.pc_i(ex_pc),
		.lane_select_i(ex_lane_select),
		.lane_select_o(ma_lane_select),
		.ddata_o(ddata_o),
		.dwrite_o(dwrite_o),
		.dsel_o(dsel_o),
		.store_value_i(ex_store_value),
		.has_writeback_i(ex_has_writeback),
		.writeback_reg_i(ex_writeback_reg),
		.writeback_is_vector_i(ex_writeback_is_vector),
		.has_writeback_o(ma_has_writeback),
		.writeback_reg_o(ma_writeback_reg),
		.writeback_is_vector_o(ma_writeback_is_vector),
		.mask_i(ex_mask),
		.mask_o(ma_mask),
		.result_i(ex_result),
		.result_o(ma_result),
		.cache_hit_i(dcache_hit_i));

	writeback_stage wbs(
		.clk(clk),
		.instruction_i(ma_instruction),
		.lane_select_i(ma_lane_select),
		.has_writeback_i(ma_has_writeback),
		.writeback_reg_i(ma_writeback_reg),
		.writeback_is_vector_i(ma_writeback_is_vector),
		.has_writeback_o(wb_has_writeback),
		.writeback_is_vector_o(wb_writeback_is_vector),
		.writeback_reg_o(wb_writeback_reg),
		.writeback_value_o(wb_writeback_value),
		.ddata_i(ddata_i),
		.result_i(ma_result),
		.mask_o(wb_writeback_mask),
		.mask_i(ma_mask));
endmodule