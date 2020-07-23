#!/usr/bin/env python
import sys
from collections import OrderedDict, defaultdict
import yaml
import math
import re

from verilogwriter import Signal, Wire, Instance, ModulePort, VerilogWriter, LocalParam, Assign, Logic

AHB3_MASTER_PORTS = [
    Signal ('HSEL'),
    Signal ('HADDR', 32),
    Signal ('HWDATA', 32),
    Signal ('HSIZE', 3),
    Signal ('HBURST', 3),
    Signal ('HPROT', 4),
    Signal ('HTRANS', 2),
    Signal ('HWRITE'),
    Signal ('HREADY'),
]
AHB3_SLAVE_PORTS = [
    Signal ('HRDATA', 32),
    Signal ('HRESP'),
    Signal ('HREADYOUT'),
]

class Parameter:
    def __init__(self, name, value):
        self.name = name
        self.value = value
        
class Port:
    def __init__(self, name, value):
        self.name = name
        self.value = value
        
class Field:
    def __init__(self, name, d=None):
        self.name = name
        self.width = 32
        self.rptr = []
        self.rtype = 'rw'
        self.count = 1
        for k, v in d.items ():
            if k == 'width':
                self.width = v;
                if v > 32:
                    raise ValueError ("width must be <= 32")
            elif k == 'type':
                if (v != 'ro') and (v != 'rw') and (v != 'wo') and (v != 'w1c'):
                    raise ValueError ("Invalid type:"+v+" valid types: ro,rw,wo,w1c")
                self.rtype = v
            elif k == 'count':
                self.count = int (v)
            else:
                raise ValueError ("Unknown prop %s" % v)
    def n(self, n):
        if self.count == 1:
            return '\t' + self.name + ':' + str(self.rptr[0].offset) + ':' + str (self.width)
        else:
            return '\t' + self.name + '[' + str(n) + ']:' + str(self.rptr[n].offset) + ':' + str (self.width)
    
class Reg:
    def __init__(self, rtype, address):
        self.rtype = rtype
        self.address = address
        if self.rtype == 'rw':
            self.access = '2\'b00';
        elif self.rtype == 'ro':
            self.access = '2\'b01';
        elif self.rtype == 'wo':
            self.access = '2\'b10';
        elif self.rtype == 'w1c':
            self.access = '2\'b11';

    def __str__(self):
        return self.rtype + ':' + '0x{:04x}'.format(self.address) + ':'

class RegPtr:
    def __init__(self, reg, offset):
        self.reg = reg
        self.offset = offset
    def __str__(self):
        return str (self.reg) + ' ' + str(self.offset)
    
class CSRGen:
    def __init__(self, config_file):
        d = OrderedDict()
        self.field = []
        self.reg = []
        import yaml

        def ordered_load(stream, Loader=yaml.Loader, object_pairs_hook=OrderedDict):
            class OrderedLoader(Loader):
                pass
            def construct_mapping(loader, node):
                loader.flatten_mapping(node)
                return object_pairs_hook(loader.construct_pairs(node))
            OrderedLoader.add_constructor(
                yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
                construct_mapping)
            return yaml.load(stream, OrderedLoader)
        data = ordered_load(open(config_file))

        config     = data['parameters']
        files_root = data['files_root']
        self.vlnv       = data['vlnv']

        # Generate name
        self.name = re.split(r'[-:]+', self.vlnv)[2]
        #if 'address' not in config.keys ():
        #    raise ValueError ("key address not found!")
        #else:
        #    self.address = config['address']
        #    print (self.name, "@", hex(self.address))

        # Get instance
        if 'instance' not in config.keys ():
            raise ValueError ("key instance not found!")
        else:
            self.instance = config['instance']

        # Create verilog writer
        self.verilog_writer = VerilogWriter (self.name)
        self.template_writer = VerilogWriter (self.name)
        
        # Sort by type then width
        regs = sorted (config['registers'].items(), key=lambda x: (x[1]['type'], 32-x[1]['width']))
        
        # Pack into registers
        rtype = 'none'
        off = 0
        addr = 0
        for k,v in regs:

            # Add field
            f = Field (k, v)

            # Loop over each count in field
            for n in range (f.count):

                # Create new register if no more space or fields have changed
                if v['type'] != rtype or (off + v['width']) > 32:
                    r = Reg (v['type'], addr)
                    off = 0
                    addr += 4
                    rtype = v['type']
                    self.reg.append (r)

                # Save register pointer
                f.rptr.append (RegPtr (r, off))
                
                # Update width
                off += v['width']
                            
            # Add field
            self.field.append (f)

        # Dump registers
        self.dump ()
        
    def dump(self):
        addr = -1
        for f in self.field:
            for n in range (f.count):
                if f.rptr[n].reg.address != addr:
                    print (f.rptr[n].reg, end='')
                    addr = f.rptr[n].reg.address
                else:
                    print ('\t', end='')
                print (f.n(n))

    def write(self):
        file = self.name + '.sv'

        # Create input/output registers
        self.verilog_writer.add (Wire ('csri', len (self.reg), prepend='[31:0]'))
        self.verilog_writer.add (Wire ('csro', len (self.reg), prepend='[31:0]'))

        # Assign wiring to registers
        for f in self.field:
            for n in range (f.count):
                rptr = f.rptr[n]
                if f.rtype == 'rw' or f.rtype == 'w1c':
                    if f.count == 1:
                        self.verilog_writer.add (Assign ('csri[' + str(int(rptr.reg.address/4)) + '][' +
                                                         str(f.width+rptr.offset-1) + ':' + str(rptr.offset) + ']',
                                                         f.name + '_i'))
                        self.verilog_writer.add (Assign (f.name + '_o', 'csro[' + str(int(rptr.reg.address/4)) +
                                                         '][' + str(f.width+rptr.offset-1) + ':' + str(rptr.offset) + ']'))
                    else:
                        self.verilog_writer.add (Assign ('csri[' + str(int(rptr.reg.address/4)) + '][' +
                                                         str(f.width+rptr.offset-1) + ':' + str(rptr.offset) + ']',
                                                         f.name + '_i[' + str(n) + ']'))
                        self.verilog_writer.add (Assign (f.name + '_o[' + str(n) + ']', 'csro[' +
                                                         str(int(rptr.reg.address/4)) + '][' +
                                                         str(f.width+rptr.offset-1) + ':' + str(rptr.offset) + ']'))


                elif f.rtype == 'ro':
                    if f.count == 1:
                        self.verilog_writer.add (Assign ('csri[' + str(int(rptr.reg.address/4)) + '][' +
                                                         str(f.width+rptr.offset-1) + ':' + str(rptr.offset) + ']',
                                                         f.name))
                    else:
                        self.verilog_writer.add (Assign ('csri[' + str(int(rptr.reg.address/4)) + '][' +
                                                         str(f.width+rptr.offset-1) + ':' + str(rptr.offset) + ']',
                                                         f.name + '[' + str(n) + ']'))
                            
                elif f.rtype == 'wo':
                    if f.count == 1:
                        self.verilog_writer.add (Assign (f.name, 'csro[' +
                                                         str(int(rptr.reg.address/4)) + '][' +
                                                         str(f.width+rptr.offset-1) + ':' + str(rptr.offset) + ']'))
                    else:
                        self.verilog_writer.add (Assign (f.name + '[' + str(n) + ']', 'csro[' +
                                                         str(int(rptr.reg.address/4)) + '][' +
                                                         str(f.width+rptr.offset-1) + ':' + str(rptr.offset) + ']'))

        # Create module
        self.verilog_writer.add(ModulePort('CLK', 'input'))
        self.verilog_writer.add(ModulePort('RESETn', 'input'))

        # Add all signals to module
        for f in self.field:
            if f.rtype == 'rw' or f.rtype == 'w1c':
                if (f.count == 1):
                    self.verilog_writer.add (ModulePort (f.name + '_i', 'input', f.width))
                    self.verilog_writer.add (ModulePort (f.name + '_o', 'output', f.width))
                else:
                    self.verilog_writer.add (ModulePort ('[' + str(f.width - 1) + ':0] ' + f.name + '_i ', 'input', f.count))
                    self.verilog_writer.add (ModulePort ('[' + str(f.width - 1) + ':0] ' + f.name + '_o ', 'output', f.count))
            elif f.rtype == 'ro':
                self.verilog_writer.add (ModulePort (f.name, 'input', f.width))
            elif f.rtype == 'wo':
                self.verilog_writer.add (ModulePort (f.name, 'output', f.width))

        # Add AHB3 ports
        for p in AHB3_MASTER_PORTS:
            self.verilog_writer.add (ModulePort (p.name, 'input', p.width))
        for p in AHB3_SLAVE_PORTS:
            self.verilog_writer.add (ModulePort (p.name, 'output', p.width))
            
        # Common params and ports
        params = [Parameter ('CNT', len (self.reg))]
        ports = [Port ('CLK', 'CLK'),
                 Port ('RESETn', 'RESETn')]
        if self.instance:
            ports += [Port (p.name, self.instance + '_' + p.name) for p in AHB3_MASTER_PORTS]
        else:
            ports += [Port (p.name, p.name) for p in AHB3_MASTER_PORTS]
        if self.instance:
            ports += [Port (p.name, self.instance + '_' + p.name) for p in AHB3_SLAVE_PORTS]
        else:
            ports += [Port (p.name, p.name) for p in AHB3_SLAVE_PORTS]
            
        # Ports only applicable to IP instantiation
        # Add access bits
        access = ''
        for r in self.reg:
            access = r.access + ',' + access;
        access = access[:-1] # remove trailing comma
        iports = [Port ('CLK', 'CLK'),
                  Port ('RESETn', 'RESETn'),
                  Port ('REGIN', 'csri'),
                  Port ('REGOUT', 'csro'),
                  Port ('ACCESS', '{' + access + '}')]
        iports += [Port (p.name, p.name) for p in AHB3_MASTER_PORTS]
        iports += [Port (p.name, p.name) for p in AHB3_SLAVE_PORTS]
        
        # Create Instance of ahb3lite_csr
        self.verilog_writer.add (Instance ('ahb3lite_csr', 'u_'+self.name, params, iports))
        self.verilog_writer.write (file)

        #
        # Generate template
        #

        # Create signal wires
        for f in self.field:
            if f.rtype == 'rw' or f.rtype == 'w1c':
                # Add wires
                if f.count == 1:
                    self.template_writer.add (Logic (f.name + '_i', f.width))
                    self.template_writer.add (Logic (f.name + '_o', f.width))
                else:
                    self.template_writer.add (Logic ('[' + str(f.width - 1) + ':0] ' + f.name + '_i', f.count))
                    self.template_writer.add (Logic ('[' + str(f.width - 1) + ':0] ' + f.name + '_o', f.count))

                # Add ports
                ports += [Port (f.name + '_i', f.name + '_i')]
                ports += [Port (f.name + '_o', f.name + '_o')]
            else:
                # Add wires
                self.template_writer.add (Logic (f.name, f.width))
                # Add ports
                ports += [Port (f.name, f.name)]

        # Insantiate custom module
        self.template_writer.add (Instance (self.name, self.name+'0', [], ports))

        # Write out file
        self.template_writer.write(file[:-2]+'vh')

        # Create core file
        core_file = self.vlnv.split(':')[2]+'.core'
        vlnv = self.vlnv
        with open(core_file, 'w') as f:
            f.write('CAPI=2:\n')
            files = [{file     : {'file_type' : 'verilogSource'}},
                     {file[:-2]+'vh' : {'is_include_file' : True,
                                  'file_type' : 'verilogSource'}}
            ]
            coredata = {'name' : vlnv,
                        'targets' : {'default' : {}},
            }

            coredata['filesets'] = {'rtl' : {'files' : files}}
            coredata['targets']['default']['filesets'] = ['rtl']

            f.write(yaml.dump(coredata))

if __name__ == "__main__":
    if len(sys.argv) == 4:
      name = sys.argv[3]
    try:
      g = CSRGen(sys.argv[1])
      print("="*80)
      g.write()
    except Error as e:
      print("Error: %s" % e)
      exit(1)
