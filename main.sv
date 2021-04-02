module main;
  parameter parallel_runs = 4;
  parameter page_size = 4096;

  int unsigned ret [parallel_runs];
  memtester tester;

  initial begin
    tester = new();

    for (int i=0; i<parallel_runs; i++) begin
      automatic k=i;

      fork tester.memtest(page_size*k, page_size/2, 0, 0, ret[k]);
      join_none
    end
    wait fork;
  end
endmodule
