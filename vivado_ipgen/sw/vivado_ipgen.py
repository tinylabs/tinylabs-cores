#!/usr/bin/env python
import sys
from collections import OrderedDict, defaultdict
import yaml
import math
import re
import os

class IPGen:
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

        # Check for vivado install root
        if 'root' in config.keys ():
            self.root = config['root']
        else:
            # Find by path
            #print (os.environ['PATH'])
            for path in os.environ['PATH'].split (':'):
                fpath = os.path.join (path, 'vivado')
                if os.path.isfile(fpath) and os.access(fpath, os.X_OK):
                    self.root = os.path.dirname(os.path.dirname (fpath))
                    break

        if not self.root:
            raise ValueError ("vivado root not found!")
        else:
            print ("vivado IPGen: " + self.root)

        # Generate full file paths
        self.files = []
        for root, dirs, files in os.walk (self.root):
            for f in config['files'].split():
                if f in files:
                    self.files.append (os.path.join (root, f))
                else:
                    ValueError (f + " not found!")                

    def write(self):

        # Create core file
        core_file = self.name + '.core'
        vlnv = self.vlnv
        with open(core_file, 'w') as f:
            f.write('CAPI=2:\n')
            files = []
            for fname in self.files:
                if fname[-2:] == '.v':
                    files.append ({fname : {'file_type' : 'verilogSource'}})
                elif fname[-3:] == '.vh':
                    files.append ({fname : {'is_include_file' : True, 'file_type' : 'verilogSource'}})
                elif fname[-4:] == '.vhd':
                    files.append ({fname : {'file_type' : 'vhdlSource'}})
            coredata = {'name' : vlnv,
                        'targets' : {'default' : {}},
            }
            #print (files)
            coredata['filesets'] = {'rtl' : {'files' : files}}
            coredata['targets']['default']['filesets'] = ['rtl']
            f.write(yaml.dump(coredata))

if __name__ == "__main__":
    if len(sys.argv) == 4:
      name = sys.argv[3]
    try:
      g = IPGen(sys.argv[1])
      print("="*80)
      g.write()
    except Error as e:
      print("Error: %s" % e)
      exit(1)
