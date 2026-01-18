#!/usr/bin/env python3
import sys
import re

def main():
    print("graph TD")
    
    # regex to match: "node_a" -> "node_b"
    # and optional label: [label = "foo"]
    edge_pattern = re.compile(r'"([^"]+)"\s*->\s*"([^"]+)"(?:\s*\[label\s*=\s*"([^"]+)"\])?')
    
    # regex to match node definition: "node_a" [label = "foo"]
    node_pattern = re.compile(r'"([^"]+)"\s*\[label\s*=\s*"([^"]+)"\]')

    # We want to skip some specific terraform nodes that clutter the graph usually
    skip_keywords = ["root", "meta.count-boundary", "var.", "provider."]

    nodes = {}
    edges = []

    for line in sys.stdin:
        line = line.strip()
        
        # Check for edges first
        edge_match = edge_pattern.search(line)
        if edge_match:
            src, dst, label = edge_match.groups()
            
            # Simple filtering
            if any(k in src for k in skip_keywords) or any(k in dst for k in skip_keywords):
                continue
                
            # Clean up names for Mermaid (remove quotes, etc if needed, but Mermaid handles strings in id if quoted? No, simpler to sanitize)
            # Terraform names usually contain dots. Mermaid might need escaping or using id/label mapping.
            # We will use hash or simplified ID for mermaid nodes and attach labels.
            
            # For simplicity, let's just use the raw names but replace quotes with nothing if they are around it?
            # The regex captures inside quotes, so src/dst are clean strings.
            
            edges.append((src, dst, label))
            continue

        # Check for node definitions (to get better labels if available)
        node_match = node_pattern.search(line)
        if node_match:
            node_id, label = node_match.groups()
            if any(k in node_id for k in skip_keywords):
                continue
            nodes[node_id] = label

    # Print definitions
    # To avoid huge graphs, we might want to just print edges using the ids, 
    # but cleaning them to valid mermaid IDs (alphanumeric).
    
    def sanitize(s):
        return re.sub(r'[^a-zA-Z0-9_]', '_', s)

    # Track printed nodes to avoid duplicates if we wanted to add class defs
    
    for src, dst, label in edges:
        s_id = sanitize(src)
        d_id = sanitize(dst)
        
        # We can try to make the label readable. 
        # Terraform node names like 'proxmox_vm_qemu.k8s_master' are good labels.
        s_lbl = src.split('.')[-1] + " (" + src.split('.')[-2] + ")" if '.' in src else src
        d_lbl = dst.split('.')[-1] + " (" + dst.split('.')[-2] + ")" if '.' in dst else dst
        
        # If we have a better label from the node def, use it? Dictionary usually has e.g. "proxmox_vm_qemu.k8s_master"
        if src in nodes:
            # nodes dict label often contains Type and Name
            pass 

        # Mermaid syntax: A[Label] --> B[Label]
        # Only attach label to node first time? 
        # Simpler: id1["name"] --> id2["name"]
        
        # Use full name as label for clarity
        print(f'    {s_id}["{src}"] --> {d_id}["{dst}"]')

if __name__ == "__main__":
    main()
