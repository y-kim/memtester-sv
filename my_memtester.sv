/*
 * The memtester class can be extended to connect drivers in your system.
 * In this example, it is connected to an internal AXI driver. (not disclosured yet)
 *
 */
class my_memtester #(
  parameter wordsize = 8,
  parameter addrwidth = 48,
  parameter ffwd = 0 // if 0 > then fast forward. number of iteration in outer-loops will be decreased.
                     // it can be used to accelerate simulation speed because RTL simulation is too slave to test everything.
) extends memtester #(wordsize, addrwidth, ffwd);

  int master_id;

  function new(string name="my_memtester", int master_id=0);
    this.name = name;
    this.master_id = master_id;
  endfunction

  virtual task automatic write_mem(addr_t addr, data_t data);
    axi_vc_pkg::transaction_t transaction;

    transaction.start_address = addr;
    transaction.direction = axi_vc_pkg::AXI_VC_WRITE;
    transaction.aid = 0;
    transaction.uid = 0;
    transaction.size = axi_vc_pkg::size_t'($clog2(wordsize));
    transaction.alen = 0;
    transaction.burst = axi_vc_pkg::AXI_VC_INCR;
    transaction.lock = 0;
    transaction.qos = 0;

    transaction.force_data = 1;
    transaction.data[0] = data;
    transaction.strb[0] = 8'hFF;
    axim_issue(master_id, transaction);
    axim_wait_tr(master_id, transaction);
  endtask

  virtual task automatic read_mem(addr_t addr, output data_t data);
    axi_vc_pkg::transaction_t transaction;
    logic [axi_id_width -1:0] axid;

    axim_get_unique_axid(master_id, axid);
    transaction.start_address = addr;
    transaction.direction = axi_vc_pkg::AXI_VC_READ;
    transaction.aid = axid;
    transaction.uid = 0;
    transaction.size = axi_vc_pkg::size_t'($clog2(wordsize));
    transaction.alen = 0;
    transaction.burst = axi_vc_pkg::AXI_VC_INCR;
    transaction.lock = 0;
    transaction.qos = 0;
    axim_issue(master_id, transaction);
    axim_wait_tr(master_id, transaction);
    data = transaction.data[0];
  endtask
endclass
