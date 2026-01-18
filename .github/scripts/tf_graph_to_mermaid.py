#!/usr/bin/env python3
import sys
import re

def main():
    print("graph TD")
    
    # Regex to match edges: "node_a" -> "node_b"
    # Handles escaped quotes in node names e.g. "provider[\"registry...\"]"
    edge_pattern = re.compile(r'"((?:[^"\\]|\\.)+)"\s*->\s*"((?:[^"\\]|\\.)+)"')

    # Regex to match node definitions (optional, but good for parsing labels if needed)
    # "node_a" [label = "foo", shape = "box"]
    # We won't use this heavily but good to have correct regex
    node_pattern = re.compile(r'"((?:[^"\\]|\\.)+)"\s*\[')

    # Keywords to skip. 
    # REMOVED "root" because OpenTofu prefixes everything with "[root]"
    # REMOVED "provider." and "var." to show full graph, or can keep if user wants simplified.
    # Let's keep it minimal to just technical internals.
    skip_keywords = ["meta.count-boundary"]

    edges = []
    
    # helper to clean node names for mermaid (remove [root], (expand), quote junk)
    def clean_label(label):
        # Remove [root] prefix
        s = label.replace("[root] ", "")
        # Remove (expand), (close) suffixes
        s = re.sub(r'\s*\((?:expand|close|reference)\)', '', s)
        # Remove "var." prefix for cleaner look (optional)
        # s = s.replace("var.", "")
        
        # If it's a provider, clean it up
        # provider["registry..."] -> provider.proxmox
        if "provider[" in s:
            match = re.search(r'provider\[\\"([^"]+)\\"\]', s)
            if match:
                # registry.opentofu.org/telmate/proxmox -> proxmox
                return "provider." + match.group(1).split('/')[-1]
            return "provider"
            
        return s

    for line in sys.stdin:
        line = line.strip()
        
        # Check for edges
        edge_match = edge_pattern.search(line)
        if edge_match:
            src_raw, dst_raw = edge_match.groups()
            
            # Use raw strings for exclusion check to be safe
            if any(k in src_raw for k in skip_keywords) or any(k in dst_raw for k in skip_keywords):
                continue
            
            src_clean = clean_label(src_raw)
            dst_clean = clean_label(dst_raw)
            
            # Avoid self-loops if cleaning made them identical
            if src_clean == dst_clean:
                continue

            edges.append((src_clean, dst_clean))

    # Print definitions
    # sanitize for ID: alphanumeric only
    def sanitize_id(s):
        return re.sub(r'[^a-zA-Z0-9_]', '_', s)

    printed_edges = set()
    
    for src, dst in edges:
        if (src, dst) in printed_edges:
            continue
        printed_edges.add((src, dst))
        
        s_id = sanitize_id(src)
        d_id = sanitize_id(dst)
        
        print(f'    {s_id}["{src}"] --> {d_id}["{dst}"]')

if __name__ == "__main__":
    main()
