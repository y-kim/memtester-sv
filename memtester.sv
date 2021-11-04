/*
 * memtester version 4 (orignal statement)
 *
 * Very simple but very effective user-space memory tester.
 * Originally by Simon Kirby <sim@stormix.com> <sim@neato.org>
 * Version 2 by Charles Cazabon <charlesc-memtester@pyropus.ca>
 * Version 3 not publicly released.
 * Version 4 rewrite:
 * Copyright (C) 2004-2020 Charles Cazabon <charlesc-memtester@pyropus.ca>
 * Licensed under the terms of the GNU General Public License version 2 (only).
 * See http://pyropus.ca/software/memtester/ for details.
 *
 */

/*
 * SystemVerilog version is ported by Yangsu Kim
 *
 */

class memtester #(
  parameter wordsize = 8,
  parameter addrwidth = 48,
  parameter ffwd = 0 // when 0 > ffwd, then fast forward is enabled. Number of iteration in outer-loops will be decreased.
                     // It can be used to accelerate simulation speed because RTL simulation is too slow to test everything.
);
  localparam UL_LEN = wordsize*8;

  typedef logic [UL_LEN-1:0] data_t;
  typedef logic [addrwidth-1:0] addr_t;
  typedef int unsigned size_t;

  localparam EXIT_FAIL_NONSTARTER   = 1;
  localparam EXIT_FAIL_ADDRESSLINES = 2;
  localparam EXIT_FAIL_OTHERTEST    = 4;

  localparam data_t ONE = 'h1;
  localparam data_t UL_ONEBITS = '1;
  localparam data_t CHECKERBOARD1 = {UL_LEN/2{2'b01}};
  localparam data_t CHECKERBOARD2 = {UL_LEN/2{2'b10}};
  localparam addr_t twowordsizemask = ~(1-(wordsize*2));

  string name;

  typedef enum {
    RAND_VAL,
    COMP_XOR,
    COMP_SUB,
    COMP_MUL,
    COMP_DIV,
    COMP_OR,
    COMP_AND,
    SEQ_INC,
    SLD_BITS,
    BLK_SEQ,
    CHKRBRD,
    BIT_SPRD,
    BIT_FLIP,
    WALK_ONE,
    WALK_ZERO
  } test_id_t;

  typedef struct {
    test_id_t id;
    string name;
  } test_t;

  test_t tests[] = '{
    '{ RAND_VAL,  "Random Value" },
    '{ COMP_XOR,  "Compare XOR" },
    '{ COMP_SUB,  "Compare SUB" },
    '{ COMP_MUL,  "Compare MUL" },
    '{ COMP_DIV,  "Compare DIV" },
    '{ COMP_OR,   "Compare OR" },
    '{ COMP_AND,  "Compare AND" },
    '{ SEQ_INC,   "Sequential Increment" },
    '{ SLD_BITS,  "Solid Bits" },
    '{ BLK_SEQ,   "Block Sequential" },
    '{ CHKRBRD,   "Checkerboard" },
    '{ BIT_SPRD,  "Bit Spread" },
    '{ BIT_FLIP,  "Bit Flip" },
    '{ WALK_ONE,  "Walking Ones" },
    '{ WALK_ZERO, "Walking Zeroes" }
  };

  // dynamic memory management for the sequence test. it is only created with the base class (memtester)
  data_t tmp_memory [addr_t];

  function new(string name="memtester");
    this.name = name;
  endfunction

  virtual task automatic write_mem(addr_t addr, data_t data);
    // place holder for memory access behavior
    addr_t wordaddr;
    wordaddr = addr/wordsize;
    #1 tmp_memory[wordaddr] = data;
  endtask

  virtual task automatic read_mem(addr_t addr, output data_t data);
    // place holder for memory access behavior
    addr_t wordaddr;
    wordaddr = addr/wordsize;
    #1 data = tmp_memory[wordaddr];
  endtask

  function logic [UL_LEN-1:0] UL_BYTE(logic [7:0] x);
    return {8{x}};
  endfunction

  function logic [UL_LEN-1:0] rand_ul();
    return {$random(), $random()};
  endfunction

  task automatic compare_regions(addr_t bufa, addr_t bufb, count, output int ret);
    ret = 0;

    for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      data_t d1, d2;

      fork
        read_mem(p1, d1);
        read_mem(p2, d2);
      join

      assert (d1 == d2) else begin
        $error("FAILURE: 0x%08x != 0x%08x at offset 0x%08x.", d1, d2, i*wordsize);
        ret = -1;
      end
    end
  endtask

  task automatic test_stuck_address(addr_t bufa, size_t count, output int ret);
    addr_t p1;

    ret = 0;

    for (int j=0; j<16; j+=ffwd ? ffwd : 1) begin
      for (int i=0, p1=bufa; i<count; i++, p1+=wordsize) begin
        write_mem(p1, ((j + i) % 2) == 0 ? p1 : ~p1);
      end

      for (int i=0, p1=bufa; i<count; i++, p1+=wordsize) begin
        data_t d1;
        read_mem(p1, d1);
        assert (d1 == (((j + i) % 2) == 0 ? p1 : ~ p1)) else begin
          $error("FAILURE: possible bad address line at offset 0x%08x.", i*wordsize);
          $error("Skipping to next test...");
          ret = -1;
        end
      end
    end
  endtask

  task automatic test_random_value(addr_t bufa, addr_t bufb, size_t count, output int ret);
    addr_t p1, p2;

    for (int i=0, p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      data_t q;

      q = rand_ul();
      fork
        write_mem(p1, q);
        write_mem(p2, q);
      join
    end

    compare_regions(bufa, bufb, count, ret);
  endtask

  task automatic test_xor_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    data_t q;

    q = rand_ul();

    for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      data_t d1, d2;

      fork
        read_mem(p1, d1);
        read_mem(p2, d2);
      join
      fork
        write_mem(p1, d1^q);
        write_mem(p2, d2^q);
      join
    end

    compare_regions(bufa, bufb, count, ret);
  endtask

  task automatic test_sub_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    data_t q;

    q = rand_ul();

    for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      data_t d1, d2;

      fork
        read_mem(p1, d1);
        read_mem(p2, d2);
      join
      fork
        write_mem(p1, d1-q);
        write_mem(p2, d2-q);
      join
    end

    compare_regions(bufa, bufb, count, ret);
  endtask

  task automatic test_mul_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    data_t q;

    q = rand_ul();

    for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      data_t d1, d2;

      fork
        read_mem(p1, d1);
        read_mem(p2, d2);
      join
      fork
        write_mem(p1, d1*q);
        write_mem(p2, d2*q);
      join
    end

    compare_regions(bufa, bufb, count, ret);
  endtask

  task automatic test_div_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    data_t q;

    q = rand_ul();

    for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      data_t d1, d2;

      fork
        read_mem(p1, d1);
        read_mem(p2, d2);
      join
      fork
        write_mem(p1, d1/q);
        write_mem(p2, d2/q);
      join
    end

    compare_regions(bufa, bufb, count, ret);
  endtask

  task automatic test_or_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    data_t q;

    q = rand_ul();

    for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      data_t d1, d2;

      fork
        read_mem(p1, d1);
        read_mem(p2, d2);
      join
      fork
        write_mem(p1, d1|q);
        write_mem(p2, d2|q);
      join
    end

    compare_regions(bufa, bufb, count, ret);
  endtask

  task automatic test_and_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    data_t q;

    q = rand_ul();

    for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      data_t d1, d2;

      fork
        read_mem(p1, d1);
        read_mem(p2, d2);
      join
      fork
        write_mem(p1, d1&q);
        write_mem(p2, d2&q);
      join
    end

    compare_regions(bufa, bufb, count, ret);
  endtask

  task automatic test_seqinc_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    data_t q;

    q = rand_ul();

    for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
      fork
        write_mem(p1, i+q);
        write_mem(p2, i+q);
      join
    end

    compare_regions(bufa, bufb, count, ret);
  endtask

  task automatic test_solidbits_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    ret = 0;

    for (int j=0; j<64; j+=ffwd ? ffwd : 1) begin
      data_t q;

      q = (j % 2) == 0 ? UL_ONEBITS : 0;

      for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
        fork
          write_mem(p1, (i % 2) == 0 ? q : ~q);
          write_mem(p2, (i % 2) == 0 ? q : ~q);
        join
      end

      compare_regions(bufa, bufb, count, ret);
      if (ret) break;
    end
  endtask

  task automatic test_checkerboard_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    ret = 0;

    for (int j=0; j<64; j+=ffwd ? ffwd : 1) begin
      data_t q;

      q = (j % 2) == 0 ? CHECKERBOARD1 : CHECKERBOARD2;

      for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
        fork
          write_mem(p1, (i % 2) == 0 ? q : ~q);
          write_mem(p2, (i % 2) == 0 ? q : ~q);
        join
      end

      compare_regions(bufa, bufb, count, ret);
      if (ret) break;
    end
  endtask

  task automatic test_blockseq_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    ret = 0;

    for (int j=0; j<256; j+=ffwd ? ffwd*4+ffwd[1:0] : 1) begin
      for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
        data_t q;

        q = UL_BYTE(j);
        fork
          write_mem(p1, q);
          write_mem(p2, q);
        join
      end

      compare_regions(bufa, bufb, count, ret);
      if (ret) break;
    end
  endtask

  task automatic test_walkbits0_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    ret = 0;

    for (int j=0; j<UL_LEN*2; j+=ffwd ? ffwd*2+ffwd[0] : 1) begin
      for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
        data_t q;

        if (j < UL_LEN) begin
          q = ONE << j;
          fork
            write_mem(p1, q);
            write_mem(p2, q);
          join
        end else begin
          q = ONE << (UL_LEN*2 -j - 1);
          fork
            write_mem(p1, q);
            write_mem(p2, q);
          join
        end
      end

      compare_regions(bufa, bufb, count, ret);
      if (ret) break;
    end
  endtask

  task automatic test_walkbits1_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    ret = 0;

    for (int j=0; j<UL_LEN*2; j+=ffwd ? ffwd*2+ffwd[0] : 1) begin
      for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
        data_t q;

        if (j < UL_LEN) begin
          q = UL_ONEBITS ^ (ONE << j);
          fork
            write_mem(p1, q);
            write_mem(p2, q);
          join
        end else begin
          q = UL_ONEBITS ^ (ONE << (UL_LEN*2 -j - 1));
          fork
            write_mem(p1, q);
            write_mem(p2, q);
          join
        end
      end

      compare_regions(bufa, bufb, count, ret);
      if (ret) break;
    end
  endtask

  task automatic test_bitspread_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    ret = 0;

    for (int j=0; j<UL_LEN*2; j+=ffwd ? ffwd*2+ffwd[0] : 1) begin
      for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
        data_t q;

        if (j < UL_LEN) begin
          q = (i % 2 == 0)
              ? (ONE << j) | (ONE << (j + 2))
              : UL_ONEBITS ^ ((ONE << j) | (ONE << (j + 2)));
          fork
            write_mem(p1, q);
            write_mem(p2, q);
          join
        end else begin
          q = (i % 2 == 0)
              ? (ONE << (UL_LEN*2 - 1 - j)) | (ONE << (UL_LEN*2 + 1 - j))
              : UL_ONEBITS ^ ((ONE << (UL_LEN*2 - 1 - j)) | (ONE << (UL_LEN*2 + 1 - j)));
          fork
            write_mem(p1, q);
            write_mem(p2, q);
          join
        end
      end

      compare_regions(bufa, bufb, count, ret);
      if (ret) break;
    end
  endtask

  task automatic test_bitflip_comparison(addr_t bufa, addr_t bufb, size_t count, output int ret);
    ret = 0;

    for (int k=0; k<UL_LEN; k+=ffwd ? ffwd*2+ffwd[0] : 1) begin
      data_t q;

      q = ONE << k;

      for (int j=0; j<8; j+=ffwd ? ffwd/2+ffwd[0] : 1) begin
        q = ~q;
        for (int i=0, addr_t p1=bufa, p2=bufb; i<count; i++, p1+=wordsize, p2+=wordsize) begin
          fork
            write_mem(p1, (i % 2) == 0 ? q : ~q);
            write_mem(p2, (i % 2) == 0 ? q : ~q);
          join
        end

        compare_regions(bufa, bufb, count, ret);
        if (ret) break;
      end
    end
  endtask

  task automatic memtest(input addr_t base, input size_t size, input loops=0, int unsigned testmask=0, output int ret);
    addr_t bufa, bufb;
    size_t count;

    // checking base and size
    if (base % (wordsize*2)) begin
      $display("FAILURE: base address is not aligned to two words");
      ret = EXIT_FAIL_NONSTARTER;
      return;
    end
    if (size % (wordsize*2)) begin
      $display("FAILURE: size is not aligned to two words");
      ret = EXIT_FAIL_NONSTARTER;
      return;
    end
    if (size == 0) begin
      $display("FAILURE: size must be greater than 0");
      ret = EXIT_FAIL_NONSTARTER;
      return;
    end

    bufa = base;
    bufb = base + size/2;
    count = size/2/wordsize;

    for (int loop=1; !loops || loop<=loops; loop++) begin
      if (loop > 0) begin
        $display("Loop %1d/%1d", loop, loops);
      end else begin
        $display("Loop %1d", loop);
      end
      $display("  [%11.3f] %s", $realtime, "Stuck Address");
      test_stuck_address(bufa, count*2, ret);
      if (ret) begin
        ret = EXIT_FAIL_ADDRESSLINES;
        return;
      end

      foreach (tests[i]) begin
        if (!testmask[i]) begin
          $display("  [%11.3f] %s", $realtime, tests[i].name);
          case (tests[i].id)
            RAND_VAL : test_random_value(bufa, bufb, count, ret);
            COMP_XOR : test_xor_comparison(bufa, bufb, count, ret);
            COMP_SUB : test_sub_comparison(bufa, bufb, count, ret);
            COMP_MUL : test_mul_comparison(bufa, bufb, count, ret);
            COMP_DIV : test_div_comparison(bufa, bufb, count, ret);
            COMP_OR  : test_or_comparison(bufa, bufb, count, ret);
            COMP_AND : test_and_comparison(bufa, bufb, count, ret);
            SEQ_INC  : test_seqinc_comparison(bufa, bufb, count, ret);
            SLD_BITS : test_solidbits_comparison(bufa, bufb, count, ret);
            BLK_SEQ  : test_blockseq_comparison(bufa, bufb, count, ret);
            CHKRBRD  : test_checkerboard_comparison(bufa, bufb, count, ret);
            BIT_SPRD : test_bitspread_comparison(bufa, bufb, count, ret);
            BIT_FLIP : test_bitflip_comparison(bufa, bufb, count, ret);
            WALK_ONE : test_walkbits1_comparison(bufa, bufb, count, ret);
            WALK_ZERO: test_walkbits0_comparison(bufa, bufb, count, ret);
          endcase
          if (ret) begin
            ret = EXIT_FAIL_OTHERTEST;
            break;
          end
        end
      end
      $display("  [%11.3f] ... Okay!", $realtime);
    end
  endtask
endclass
