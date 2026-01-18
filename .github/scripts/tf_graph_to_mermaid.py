#!/usr/bin/env python3
import sys
import re
import json
import os

def load_plan_details(plan_file):
    """
    Parses tofu plan JSON to map resource addresses to their details.
    Returns dict: { "resource_address": "HTML Label Context" }
    """
    params = {}
    if not os.path.exists(plan_file):
        return params
        
    try:
        with open(plan_file, 'r') as f:
            data = json.load(f)
            
        # Iterate over resource changes
        for resource in data.get('resource_changes', []):
            address = resource.get('address')
            change = resource.get('change', {})
            after = change.get('after', {})
            
            # Skip if no configuration (e.g. data sources might be different)
            if not after:
                continue

            details = []
            
            # 1. OS / Template (clone)
            clone = after.get('clone')
            if clone:
                details.append(f"OS: {clone}")
            
            # 2. IP Address (ipconfig0)
            # Format usually: "ip=192.168.0.x/24,gw=..."
            ipconfig0 = after.get('ipconfig0')
            if ipconfig0:
                # Extract just the IP part
                ip_match = re.search(r'ip=([^,]+)', ipconfig0)
                if ip_match:
                    details.append(f"IP: {ip_match.group(1)}")
                else:
                    details.append(f"IP: {ipconfig0}")
            
            # 3. Disk Size
            # disks is usually a list of dicts or complex structure in newer provider versions
            # But in the provided main.tf it uses blocks.
            # In JSON 'after', blocks are often lists of dicts.
            # Check 'disks' block first (if using new structure) or flat 'disk' properties
            
            # Based on main.tf: disks { scsi { scsi0 { disk { size = ... } } } }
            # In JSON this might be deeply nested.
            
            disk_size = None
            disks = after.get('disks', [])
            if disks and isinstance(disks, list):
                # Try to traverse: [0] -> scsi -> [0] -> scsi0 -> [0] -> disk -> [0] -> size
                try:
                    # Simplify: Look for explicit size in known structure or generic traversal
                    # Let's try to find 'size' in the first disk found
                    scsi = disks[0].get('scsi', [])
                    if scsi:
                        scsi0 = scsi[0].get('scsi0', [])
                        if scsi0:
                            disk_block = scsi0[0].get('disk', [])
                            if disk_block:
                                disk_size = disk_block[0].get('size')
                except (IndexError, AttributeError):
                    pass
            
            # Fallback for simpler 'disk' attribute if used, or root level 'disk_size'? 
            # In proxmox provider, sometimes it is just 'disk' list.
            # Let's check root level 'disk' if 'disks' was empty?
            
            if disk_size:
                 details.append(f"Disk: {disk_size}")

            if details:
                params[address] = "<br/>".join(details)
                
    except Exception as e:
        # If parsing fails, just ignore details to not break the pipeline
        sys.stderr.write(f"Warning: Failed to parse plan JSON: {e}\n")
        
    return params

def main():
    # If 2nd arg provided, it is the plan json path
    plan_file = sys.argv[1] if len(sys.argv) > 1 else None
    
    resource_details = {}
    if plan_file:
         resource_details = load_plan_details(plan_file)

    print("graph TD")
    
    # Regex to match edges: "node_a" -> "node_b"
    edge_pattern = re.compile(r'"((?:[^"\\]|\\.)+)"\s*->\s*"((?:[^"\\]|\\.)+)"')

    # Keywords to skip.
    skip_keywords = ["meta.count-boundary"]

    edges = []
    
    def clean_label(label):
        s = label.replace("[root] ", "")
        s = re.sub(r'\s*\((?:expand|close|reference)\)', '', s)
        
        # provider["registry..."] -> provider.proxmox
        if "provider[" in s:
            match = re.search(r'provider\[\\"([^"]+)\\"\]', s)
            if match:
                return "provider." + match.group(1).split('/')[-1]
            return "provider"
        return s

    for line in sys.stdin:
        line = line.strip()
        edge_match = edge_pattern.search(line)
        if edge_match:
            src_raw, dst_raw = edge_match.groups()
            
            if any(k in src_raw for k in skip_keywords) or any(k in dst_raw for k in skip_keywords):
                continue
            
            src_clean = clean_label(src_raw)
            dst_clean = clean_label(dst_raw)
            
            if src_clean == dst_clean:
                continue

            edges.append((src_clean, dst_clean))

    # sanitize for ID
    def sanitize_id(s):
        return re.sub(r'[^a-zA-Z0-9_]', '_', s)

    printed_nodes = set()
    printed_edges = set()
    
    # Pre-print nodes with labels if we have details
    # We iterate edges to find all nodes
    all_nodes = set()
    for src, dst in edges:
        all_nodes.add(src)
        all_nodes.add(dst)
        
    for node in all_nodes:
        node_id = sanitize_id(node)
        
        # Look up details in plan map
        # key in plan is usually "module.x.resource.y"
        # our node name is usually "resource.y", we might need partial match if module is stripped?
        # But 'clean_label' kept module prefix (if any).
        # Tofu graph output usually includes full address.
        
        # Exact match attempt
        details = resource_details.get(node)
        
        label_html = node
        if details:
            # HTML Label for Mermaid
            # Using bold identifying name and details
            # If node name is long, maybe split?
            short_name = node.split('.')[-1]
            label_html = f"<b>{short_name}</b><br/>{details}"
        
        # Print node definition with label
        # id["label"]
        print(f'    {node_id}["{label_html}"]')
        printed_nodes.add(node)

    # Print attributes/styles? No, just connections now
    for src, dst in edges:
        if (src, dst) in printed_edges:
            continue
        printed_edges.add((src, dst))
        
        s_id = sanitize_id(src)
        d_id = sanitize_id(dst)
        
        print(f'    {s_id} --> {d_id}')

if __name__ == "__main__":
    main()
