SET search_path = public, ag_catalog, "$user";

SELECT * FROM cypher('case_graph', $$
    MATCH (n)-[r]->(m)
    RETURN n, r, m
$$) AS (source agtype, edge agtype, target agtype);