/* -*- P4_16 -*- */

/*
 * P4 Calculator
 *
 * This program implements a simple protocol. It can be carried over Ethernet
 * (Ethertype 0x1234).
 *
 * The Protocol header looks like this:
 *
 *        0                1                  2              3
 * +----------------+----------------+----------------+---------------+
 * |      P         |       4        |     Version    |     Op        |
 * +----------------+----------------+----------------+---------------+
 * |                              Operand A                           |
 * +----------------+----------------+----------------+---------------+
 * |                              Operand B                           |
 * +----------------+----------------+----------------+---------------+
 * |                              Result                              |
 * +----------------+----------------+----------------+---------------+
 *
 * P is an ASCII Letter 'P' (0x50)
 * 4 is an ASCII Letter '4' (0x34)
 * Version is currently 0.1 (0x01)
 * Op is an operation to Perform:
 *   '+' (0x2b) Result = OperandA + OperandB
 *   '-' (0x2d) Result = OperandA - OperandB
 *   '&' (0x26) Result = OperandA & OperandB
 *   '|' (0x7c) Result = OperandA | OperandB
 *   '^' (0x5e) Result = OperandA ^ OperandB
  *   '|' (0x52) Result = OperandA R (Reset register aggretor with value of OperandA)
 *   '^' (0x41) Result = OperandA A (Add to register aggregator operandA)
 *
 * The device receives a packet, performs the requested operation, fills in the 
 * result and sends the packet back out of the same port it came in on, while 
 * swapping the source and destination addresses.
 *
 * If an unknown operation is specified or the header is not valid, the packet
 * is dropped 
 */

#include <core.p4>
#include <v1model.p4>

/*
 * Define the headers the program will recognize
 */

/*
 * Standard ethernet header 
 */
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

/*
 * This is a custom protocol header for the calculator. We'll use 
 * ethertype 0x1234 for is (see parser)
 */
const bit<16> P4CALC_ETYPE = 0x1234;
const bit<16> P4AGGR_ETYPE = 0x2234;

const bit<8>  P4CALC_P     = 0x50;   // 'P'
const bit<8>  P4CALC_4     = 0x34;   // '4'
const bit<8>  P4CALC_VER   = 0x01;   // v0.1
const bit<8>  P4CALC_PLUS  = 0x2b;   // '+'
const bit<8>  P4CALC_MINUS = 0x2d;   // '-'
const bit<8>  P4CALC_AND   = 0x26;   // '&'
const bit<8>  P4CALC_OR    = 0x7c;   // '|'
const bit<8>  P4CALC_CARET = 0x5e;   // '^'

const bit<8>  P4AGGR_RESET = 0x52;   // 'R'
const bit<8>  P4AGGR_ADD = 0x41;   // 'A'
const bit<32>  MAX_COUNT = 0x03;

header p4calc_t {
    bit<8>  p;
    bit<8>  four;
    bit<8>  ver;
    bit<8>  op;
    bit<32> operand_a;
    bit<32> operand_b;
    bit<32> res;
}

/*
 * All headers, used in the program needs to be assembed into a single struct.
 * We only need to declare the type, but there is no need to instantiate it,
 * because it is done "by the architecture", i.e. outside of P4 functions
 */
struct headers {
    ethernet_t   ethernet;
    p4calc_t     p4calc;
}

/*
 * All metadata, globally used in the program, also  needs to be assembed 
 * into a single struct. As in the case of the headers, we only need to 
 * declare the type, but there is no need to instantiate it,
 * because it is done "by the architecture", i.e. outside of P4 functions
 */

struct ingress_metadata_t {
    bit<32> agg_counter;
    bit<32> agg_register;
}

struct metadata {
    /* In our case it is empty */
    ingress_metadata_t ingress_metadata;
}


/*************************************************************************
 ***********************  P A R S E R  ***********************************
 *************************************************************************/
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            P4CALC_ETYPE   : check_p4calc;
            //P4AGGR_ETYPE     : check_p4calc;
            default      : accept;
        }
    }
    
    state check_p4calc {
        transition select(packet.lookahead<p4calc_t>().p,
        packet.lookahead<p4calc_t>().four,
        packet.lookahead<p4calc_t>().ver) {
            (P4CALC_P, P4CALC_4, P4CALC_VER) : parse_p4calc;
            default                          : accept;
        }
    }
    
    state parse_p4calc {
        //meta.ingress_metadata.agg_counter = 0x0;
        //meta.ingress_metadata.agg_register = 0x0;
        packet.extract(hdr.p4calc);
        transition accept;
    }
}

/*************************************************************************
 ************   C H E C K S U M    V E R I F I C A T I O N   *************
 *************************************************************************/
control MyVerifyChecksum(inout headers hdr,
                         inout metadata meta) {
    apply { }
}

/*************************************************************************
 **************  I N G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
               
    register <bit <32>> (1) aggregator;
    register <bit <32>> (1) aggcounter;

    bit<32> agg_val;
    bit<32> count_val;
    
    action send_back() {
        bit<48> tmp;

        /* Swap the MAC addresses */
        tmp = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = hdr.ethernet.srcAddr;
        hdr.ethernet.srcAddr = tmp;
        
        /* Send the packet back to the port it came from */
        standard_metadata.egress_spec = standard_metadata.ingress_port;
    }
    
     action set_result(bit<32> result) {
        /* Put the result back in */
        hdr.p4calc.res = result;
    }

     action set_agg_hdr() {
        /* Put the result back in */
        aggregator.read(hdr.p4calc.res, 0x0); //= meta.agg_register;
    }
    
     action set_count_hdr() {
        /* Put the result back in */
        aggcounter.read(hdr.p4calc.operand_b, 0x0);  //meta.agg_counter; //meta.agg_register;
    }
        
    action operation_add() {
        set_result(hdr.p4calc.operand_a + hdr.p4calc.operand_b);
    }
    
    action operation_sub() {
        set_result(hdr.p4calc.operand_a - hdr.p4calc.operand_b);
    }
    
    action operation_and() {
        set_result(hdr.p4calc.operand_a & hdr.p4calc.operand_b);
    }
    
    action operation_or() {
        set_result(hdr.p4calc.operand_a | hdr.p4calc.operand_b);
    }

    action operation_xor() {
        set_result(hdr.p4calc.operand_a ^ hdr.p4calc.operand_b);
    }

    action add_aggregator() {
        
        bit <32> agg = 0x0;
        //bit <32> index = 0x0;
        //aggregator.read(agg, 0x0);
        //agg = agg + hdr.p4calc.operand_a;
        //aggregator.write(0x0, agg);
        //send_back(aggcount);
        //mark_to_drop();
        
        /*aggregator.read(meta.ingress_metadata.agg_register, 0x0);
        meta.ingress_metadata.agg_register = meta.ingress_metadata.agg_register + hdr.p4calc.operand_a;
        aggregator.write(0x0, meta.ingress_metadata.agg_register);*/

        aggregator.read(hdr.p4calc.res, 0x0);
        hdr.p4calc.res = hdr.p4calc.res + hdr.p4calc.operand_a;
        aggregator.write(0x0, hdr.p4calc.res);

        /*aggregator.read(agg, 0x0);
        agg = agg + hdr.p4calc.operand_a;
        aggregator.write(0x0, agg);*/
    }

    action inc_counter() {
        bit <32> aggcount = 0x0;
        //bit <32> index = 0x0;
        //aggcounter.read(aggcount, 0x0);
        //aggcount = aggcount + 0x1;
        //aggcounter.write(0x0, aggcount);

        /*aggcounter.read(meta.ingress_metadata.agg_counter , 0x0);
        meta.ingress_metadata.agg_counter = meta.ingress_metadata.agg_counter + 1; 
        aggcounter.write(0x0,  meta.ingress_metadata.agg_counter);*/

        aggcounter.read(hdr.p4calc.operand_b , 0x0);
        hdr.p4calc.operand_b = hdr.p4calc.operand_b  + 1; 
        aggcounter.write(0x0,  hdr.p4calc.operand_b);

        /*aggcounter.read(aggcount , 0x0);
        aggcount = aggcount  + 1; 
        aggcounter.write(0x0,  aggcount);*/
    }

    action read_aggregator() {
        //bit <32> index = 0x0;
        aggregator.read(hdr.p4calc.res, 0x0);
        //aggregator.read(meta.ingress_metadata.agg_register, 0x0);
        //aggregator.read(agg_val, 0x0);
        //send_back(agg);
    }

     action read_counter() {
        //bit <32> index = 0x0;
        aggcounter.read(hdr.p4calc.operand_b, 0x0);
        //aggcounter.read(meta.ingress_metadata.agg_counter, 0x0);
        //aggcounter.read(count_val, 0x0);
        //aggcounter.read(hdr.p4calc.res, 0x0);
        //send_back(agg);
    }

    action reset_aggregator() {
        //meta.ingress_metadata.agg_register = hdr.p4calc.operand_a;
        //bit <32> index = 0x0;
        //aggregator.write(0x0, agg);
        //aggregator.read(agg, 0x0);
        //send_back(agg);
        //aggregator.write(0x0, meta.ingress_metadata.agg_register);
        //aggregator.read(meta.agg_register, 0x0);
        aggregator.write(0x0, hdr.p4calc.operand_a);
    }

    action reset_counter() {
        //bit <32> val = 0x0;
        //meta.ingress_metadata.agg_counter = 0x0;
        //aggcounter.write(0x0, meta.ingress_metadata.agg_counter);

        aggcounter.write(0x0, 0x0);
    }

    action operation_drop() {
        mark_to_drop();
    }
        
    table calculate {
        key = {
            hdr.p4calc.op        : exact;
        }
        actions = {
            operation_add;
            operation_sub;
            operation_and;
            operation_or;
            operation_xor;
            operation_drop;
        }
        const default_action = operation_drop();
        const entries = {
            P4CALC_PLUS : operation_add();
            P4CALC_MINUS: operation_sub();
            P4CALC_AND  : operation_and();
            P4CALC_OR   : operation_or();
            P4CALC_CARET: operation_xor();
        }
    }

    table aggtab {

        key = {
             hdr.p4calc.op     : exact;
        }
        actions = {
                reset_aggregator;
                add_aggregator;
        }
        const default_action = reset_aggregator();
        const entries = {
            P4AGGR_RESET: reset_aggregator();
            P4AGGR_ADD: add_aggregator();
        }
     }

    table countertab {
        key = {
             hdr.p4calc.op      : exact;
        }
        actions = {
             reset_counter;
             inc_counter;
        }
        const default_action = reset_counter();
        const entries = {
            P4AGGR_RESET: reset_counter();
            P4AGGR_ADD: inc_counter();
            }
    }

    table set_count_tab {
        key = {
              hdr.p4calc.operand_b  : exact;
        }
        actions = {
             set_count_hdr;
        }
        const default_action = set_count_hdr; //send_counter;
        //const entries = {
         //   0x4: send_register();
        //}
    }

    table set_agg_tab {
        key = {
              hdr.p4calc.res  : exact;
        }
        actions = {
             set_agg_hdr;
        }
        const default_action = set_agg_hdr; //send_counter;
        //const entries = {
         //   0x4: send_register();
        //}
    }
            
    apply {
        //read_counter();
        //read_aggregator();
        /*if ( meta.agg_counter > MAX_COUNT) {
                countertab.apply();
                send_back(meta.agg_register);   
                exit;
        }
        else {*/
        if (hdr.p4calc.isValid()) {                  
                    
                    if ( hdr.p4calc.op == 0x41 || hdr.p4calc.op == 0x52)
                    {
                        aggtab.apply();
                        countertab.apply();
                        //read_aggregator();
                        //read_counter();

                        //meta.ingress_metadata.agg_counter = count_val;
                        //meta.ingress_metadata.agg_register = agg_val)
                        //if (meta.ingress_metadata.agg_counter > MAX_COUNT) //(  hdr.p4calc.res > MAX_COUNT)
                        //if (count_val > MAX_COUNT)
                        //sendout.apply();
                        set_agg_tab.apply();
                        set_count_tab.apply();
                        if (  hdr.p4calc.operand_b > MAX_COUNT)
                        {
                               //set_agg_hdr();
                               //set_count_hdr();
                               send_back();

                        }
                        /*else
                        {
                            operation_drop();
                        }*/
                    }
                    else
                    {
                        calculate.apply();
                        send_back();
                    }
         } 
         else{
                operation_drop();
         }
     }
}

/*************************************************************************
 ****************  E G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

/*************************************************************************
 *************   C H E C K S U M    C O M P U T A T I O N   **************
 *************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

/*************************************************************************
 ***********************  D E P A R S E R  *******************************
 *************************************************************************/
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.p4calc);
    }
}

/*************************************************************************
 ***********************  S W I T T C H **********************************
 *************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
