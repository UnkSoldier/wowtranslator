local name, ns = ...
table.insert(ns.order, "Second")
ns.secondSawSameNs = (ns == FakeAddon_NS)
ns.secondName = name
