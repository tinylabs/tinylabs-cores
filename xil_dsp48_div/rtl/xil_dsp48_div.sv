/**
 *  Create a clock divider using the DSP48 hard block on Xilinx 7-series
 *  The idea is a very fast internal clock can run. When the DSP matches
 *  the value the output clock will toggle.
 * 
 *  All rights reserved.
 *  Tiny Labs Inc
 *  2020
 */

module xil_dsp48_div (
                      input        CLKIN,
                      input [31:0] SEL,
                      output logic CLKOUT
                      );

   logic                           match;
   
   // Invert clock on match
   always @(posedge CLKIN)
     CLKOUT <= match ? ~CLKOUT : CLKOUT;
   
   
   DSP48E1 #(
             //FeatureControlAttributes:DataPathSelection
             .A_INPUT("DIRECT"),               //SelectsAinputsource,"DIRECT"(Aport)or"CASCADE"(ACINport)
             .B_INPUT("DIRECT"),               //SelectsBinputsource,"DIRECT"(Bport)or"CASCADE"(BCINport)
             .USE_DPORT("FALSE"),              //SelectDportusage(TRUEorFALSE)
             //Selectmultiplierusage("MULTIPLY","DYNAMIC",or"NONE")
             //PatternDetectorAttributes:PatternDetectionConfiguration
             .USE_MULT("NONE"),
             .AUTORESET_PATDET("RESET_MATCH"), //"NO_RESET","RESET_MATCH","RESET_NOT_MATCH"
             .MASK(48'h0),                     //48-bitmaskvalueforpatterndetect(1=ignore)
             .PATTERN(48'h000000000000),       //48-bitpatternmatchforpatterndetect
             .SEL_MASK("MASK"),                //"C","MASK","ROUNDING_MODE1","ROUNDING_MODE2"
             .SEL_PATTERN("C"),                //Selectpatternvalue("PATTERN"or"C")
             //RegisterControlAttributes:PipelineRegisterConfiguration
             //Enablepatterndetect("PATDET"or"NO_PATDET")
             .USE_PATTERN_DETECT("PATDET"),
             .ACASCREG(1),                     //NumberofpipelinestagesbetweenA/ACINandACOUT(0,1or2)
             .ADREG(1),                        //Numberofpipelinestagesforpre-adder(0or1)
             .ALUMODEREG(1),                   //NumberofpipelinestagesforALUMODE(0or1)
             .AREG(1),                         //NumberofpipelinestagesforA(0,1or2)
             .BCASCREG(1),                     //NumberofpipelinestagesbetweenB/BCINandBCOUT(0,1or2)
             .BREG(1),                         //NumberofpipelinestagesforB(0,1or2)
             .CARRYINREG(1),                   //NumberofpipelinestagesforCARRYIN(0or1)
             .CARRYINSELREG(1),                //NumberofpipelinestagesforCARRYINSEL(0or1)
             .CREG(1),                         //NumberofpipelinestagesforC(0or1)
             .DREG(1),                         //NumberofpipelinestagesforD(0or1)
             .INMODEREG(1),                    //NumberofpipelinestagesforINMODE(0or1)
             .MREG(0),                         //Numberofmultiplierpipelinestages(0or1)
             .OPMODEREG(1),                    //NumberofpipelinestagesforOPMODE(0or1)
             .PREG(1),                         //NumberofpipelinestagesforP(0or1)
             .USE_SIMD("ONE48")                //SIMDselection("ONE48","TWO24","FOUR12")
             )
   u_dsp48_div (
                //Cascade:30-bit(each)output:CascadePorts
                .ACOUT(),                 //30-bit output:A portcascadeoutput
                .BCOUT(),                 //18-bit output:B portcascadeoutput
                .CARRYCASCOUT(),          //1-bit output:Cascadecarryoutput
                .MULTSIGNOUT(),           //1-bit output:Multipliersigncascadeoutput
                .PCOUT(),                 //48-bit output:Cascadeoutput
                //Control:1-bit(each)output:ControlInputs/StatusBits
                .OVERFLOW(),              //1-bitoutput:Overflowinadd/accoutput
                .PATTERNBDETECT(),        //1-bitoutput:Patternbardetectoutput
                .PATTERNDETECT(match),    //1-bitoutput:Patterndetectoutput
                .UNDERFLOW(),             //1-bitoutput:Underflowinadd/accoutput
                //Data:4-bit(each)output:DataPorts
                .CARRYOUT(),              //4-bitoutput:Carryoutput
                .P(),                     //48-bitoutput:Primarydataoutput
                //Cascade:30-bit(each)input:CascadePorts
                .ACIN(30'h0),             //30-bitinput:Acascadedatainput
                .BCIN(18'h0),             //18-bitinput:Bcascadeinput
                .CARRYCASCIN(1'b0),       //1-bitinput:Cascadecarryinput
                .MULTSIGNIN(1'b0),        //1-bitinput:Multipliersigninput
                .PCIN(48'h0),             //48-bitinput:Pcascadeinput
                //Control:4-bit(each)input:ControlInputs/StatusBits
                .ALUMODE(4'h0),           //4-bitinput:ALUcontrolinput
                .CARRYINSEL(3'h0),        //3-bitinput:Carryselectinput
                .CEINMODE(1'b1),          //1-bitinput:ClockenableinputforINMODEREG
                .CLK(CLKIN),              //1-bitinput:Clockinput
                .INMODE(5'h0),            //5-bitinput:INMODEcontrolinput
                .OPMODE(7'h0),            //7-bitinput:Operationmodeinput
                .RSTINMODE(1'b0),         //1-bitinput:ResetinputforINMODEREG
                // Data:
                // 30-bit(each)input:DataPorts
                .A(30'h1),                //30-bitinput:Adatainput
                .B(18'h0),                //18-bitinput:Bdatainput
                .C({16'h0, SEL}),         //48-bitinput:Cdatainput
                .CARRYIN(1'b0),           //1-bitinput:Carryinputsignal
                .D(25'h0),                //25-bit input:Ddatainput
                // Reset/ClockEnable:
                // 1-bit(each)input : Reset/ClockEnableInputs
                .CEA1(1'b1),              //1-bitinput:Clockenableinputfor1ststageAREG
                .CEA2(1'b1),              //1-bitinput:Clockenableinputfor2ndstageAREG
                .CEAD(1'b1),              //1-bitinput:ClockenableinputforADREG
                .CEALUMODE(1'b1),         //1-bitinput:ClockenableinputforALUMODERE
                .CEB1(1'b1),              //1-bitinput:Clockenableinputfor1ststageBREG
                .CEB2(1'b1),              //1-bitinput:Clockenableinputfor2ndstageBREG
                .CEC(1'b1),               //1-bitinput:ClockenableinputforCREG
                .CECARRYIN(1'b1),         //1-bitinput:ClockenableinputforCARRYINREG
                .CECTRL(1'b1),            //1-bitinput:ClockenableinputforOPMODEREGandCARRYINSELREG
                .CED(1'b1),               //1-bitinput:ClockenableinputforDREG
                .CEM(1'b1),               //1-bitinput:ClockenableinputforMREG
                .CEP(1'b1),               //1-bitinput:ClockenableinputforPREG
                .RSTA(1'b0),              //1-bitinput:ResetinputforAREG
                .RSTALLCARRYIN(1'b0),     //1-bitinput:ResetinputforCARRYINREG
                .RSTALUMODE(1'b0),        //1-bitinput:ResetinputforALUMODEREG
                .RSTB(1'b0),              //1-bitinput:ResetinputforBREG
                .RSTC(1'b0),              //1-bitinput:ResetinputforCREG
                .RSTCTRL(1'b0),           //1-bitinput:ResetinputforOPMODEREGandCARRYINSELREG
                .RSTD(1'b0),              //1-bitinput:ResetinputforDREGandADREG
                .RSTM(1'b0),              //1-bitinput:ResetinputforMREG
                .RSTP(1'b0)               //1-bitinput:ResetinputforPREG
                );

endmodule // xil_dsp48_div

