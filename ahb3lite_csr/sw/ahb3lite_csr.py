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
    def __init__(self, name, offset, d=None):
        self.name = name
        self.offset = offset
        self.width = 32
        self.rtype = 'rw'
        for k, v in d.items ():
            if k == 'width':
                self.width = v;
                if v > 32:
                    raise ValueError ("width must be <= 32")
            elif k == 'type':
                if (v != 'ro') and (v != 'rw') and (v != 'wo') and (v != 'w1c'):
                    raise ValueError ("Invalid type:"+v+" valid types: ro,rw,wo,w1c")
                self.rtype = v
            else:
                raise ValueError ("Unknown prop %s" % v)
    def __str__(self):
        if self.offset:
            s = '\t'
        else:
            s = ''
        s += hex (self.offset) + ': ' + self.name + ':' + str(self.width)
        return s
    
class Reg:
    def __init__(self, rtype, offset):
        self.field = []
        self.rtype = rtype
        self.offset = offset
        if self.rtype == 'rw':
            self.access = '2\'b00';
        elif self.rtype == 'ro':
            self.access = '2\'b01';
        elif self.rtype == 'wo':
            self.access = '2\'b10';
        elif self.rtype == 'w1c':
            self.access = '2\'b11';

    def __str__(self):
        s = hex(self.offset) + ':(' + self.rtype + ')'
        for f in self.field:
            s += '\t' + str(f) + '\n'
        return s.rstrip()
    
class CSRGen:
    def __init__(self, config_file):
        d = OrderedDict()
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
        if 'address' not in config.keys ():
            raise ValueError ("key address not found!")
        else:
            self.address = config['address']
            print (self.name, "@", hex(self.address))

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

            # Create new register if no more space or fields have changed
            if v['type'] != rtype or (off + v['width']) >= 32:
                r = Reg (v['type'], addr)
                self.reg.append(r)
                off = 0
                addr += 4
                rtype = v['type']
                
            # Add field
            r.field.append (Field (k, off, v))
            off += v['width']

        # Dump registers
        self.dump ()
        
    def dump(self):
        for r in self.reg:
            print (r)

    def write(self):
        file = self.name + '.sv'

        # Create input/output registers
        self.verilog_writer.add (Wire ('csri', len (self.reg), prepend='[31:0]'))
        self.verilog_writer.add (Wire ('csro', len (self.reg), prepend='[31:0]'))

        # Assign wiring to registers
        for r in self.reg:
            for f in r.field:
                if r.rtype == 'rw' or r.rtype == 'w1c':
                    self.verilog_writer.add (Assign ('csri['+str((int(r.offset/4)))+']['+
                                                     str(f.width+f.offset-1)+':'+str(f.offset)+']', f.name + '_i'))
                    self.verilog_writer.add (Assign (f.name + '_o', 'csro['+str((int(r.offset/4)))+']['+
                                                     str(f.width+f.offset-1)+':'+str(f.offset)+']'))
                elif r.rtype == 'ro':
                    self.verilog_writer.add (Assign ('csri['+str((int(r.offset/4)))+']['+
                                                     str(f.width+f.offset-1)+':'+str(f.offset)+']', f.name))
                elif r.rtype == 'wo':
                    self.verilog_writer.add (Assign (f.name, 'csro['+str((int(r.offset/4)))+']['+
                                                     str(f.width+f.offset-1)+':'+str(f.offset)+']'))

        # Create module
        self.verilog_writer.add(ModulePort('CLK', 'input'))
        self.verilog_writer.add(ModulePort('RESETn', 'input'))

        # Add all signals to module
        for r in self.reg:
            for f in r.field:
                if r.rtype == 'rw' or r.rtype == 'w1c':
                    self.verilog_writer.add (ModulePort (f.name + '_i', 'input', f.width))
                    self.verilog_writer.add (ModulePort (f.name + '_o', 'output', f.width))
                elif r.rtype == 'ro':
                    self.verilog_writer.add (ModulePort (f.name, 'input', f.width))
                elif r.rtype == 'wo':
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
        ports += [Port (p.name, self.instance + '_' + p.name) for p in AHB3_MASTER_PORTS]
        ports += [Port (p.name, self.instance + '_' + p.name) for p in AHB3_SLAVE_PORTS]

        # Ports only applicable to IP instantiation
        # Add access bits
        access = '';
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
        for r in self.reg:
            for f in r.field:
                if r.rtype == 'rw' or r.rtype == 'w1c':
                    # Add wires
                    self.template_writer.add (Logic (f.name + '_i', f.width))
                    self.template_writer.add (Logic (f.name + '_o', f.width))
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
