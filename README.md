# LAB511: Create advanced Postgres-powered agentic apps with Azure HorizonDB

## Overview

This Microsoft Build 2026 lab walks you through building an **agentic legal research application** end to end, powered by a single **Azure HorizonDB** (Postgres) instance acting as your relational store, full-text search engine, vector database, graph database, **and** long-term memory store for the agent.

You will load a real U.S. case-law dataset, light up the AI extensions inside HorizonDB, and then assemble a Microsoft Agent Framework agent that combines **BM25 keyword search**, **vector similarity (DiskANN)**, **citation-graph traversal (Apache AGE)**, **in-database entity extraction (`azure_ai`)**, and an **external weather API** to write a real legal brief, with persistent memory across turns.

The lab is intentionally hands-on: every concept is paired with a runnable notebook cell, a Technical Background Notes block explaining what is happening underneath, and a short Tasks list telling you what to look at in the output.

## Architecture

![Architecture](./Docs/images/arch.png)

## Application UI

![Application UI](./Docs/images/app_ui.png)

## What You'll Build

- A **Microsoft Agent Framework** agent that can reason over U.S. case law stored in Azure HorizonDB.
- **Hybrid retrieval**: BM25 full-text search (`pg_fts`) combined with vector similarity search (`pgvector` + `pg_diskann` for ANN with advanced filtering).
- **GraphRAG** over a citation graph built with **Apache AGE**, letting the agent expand from anchor cases to surrounding precedents in a single Cypher-style traversal.
- **In-database entity extraction** with the `azure_ai` extension, so structured fields (`holding`, `issues`, `statutes_cited`, `disposition`) are pulled directly inside Postgres instead of round-tripping opinions back to the application.
- **External evidence ingestion** through a tool that calls the Open-Meteo weather archive API.
- **Long-term memory** with **Mem0**, where memory embeddings are stored back in the same HorizonDB instance using `pgvector`. No separate vector database.
- A **Gradio chat UI** that surfaces a live Tool Trace panel and the agent's growing memory store next to the conversation.

## Key Technologies

- **Azure HorizonDB**: managed Postgres with a rich AI extension surface (`vector`, `pg_diskann`, `pg_fts`, `azure_ai`, `age`).
- **Microsoft Agent Framework**: open-source SDK for building tool-using agents (`OpenAIChatClient`, `@tool` decorator, `client.as_agent(...)`).
- **Azure OpenAI**: GPT chat deployment for the agent and `text-embedding-3-small` (1536 dims) for case and memory embeddings.
- **Apache AGE**: property-graph engine inside Postgres for the citation graph (`(:case)-[:REF]->(:case)`).
- **Mem0**: long-term memory layer for agents, configured here against `pgvector` in HorizonDB.
- **Gradio**: web UI for the finished agent, embedded directly in the notebook.
- **Python**: notebooks driven by `psycopg`, `openai`, `agent-framework`, `mem0`, and `gradio`.

## Project Structure

```
├── LICENSE                       # MIT License
├── requirements.txt              # Python package dependencies for the lab
├── README.md                     # This file
├── Code/
│   ├── 1-data-setup.ipynb        # Notebook 1: load cases, build indexes, build the graph
│   ├── 2-app-development.ipynb   # Notebook 2: build the 5-tool agent + Mem0 + Gradio UI
│   └── 3-diagnostics.ipynb       # Diagnostics / troubleshooting helpers
├── Dataset/
│   └── cases.csv                 # U.S. case-law dataset used throughout the lab
├── Docs/                         # Lab documentation and architecture images
├── Infra/
│   ├── deploy-hdb.bicep          # Bicep template for the HorizonDB instance
│   ├── deploy.bicep              # Top-level Bicep template (full lab environment)
│   └── deploy.ps1                # PowerShell wrapper for the deployment
└── Scripts/
    ├── show_graph.sql            # Sample SQL for inspecting the AGE citation graph
    └── Lab Internals/            # Scripts used to build and validate the lab VM image
```

## Prerequisites

- An **Azure subscription** with access to **Azure OpenAI** and **Azure HorizonDB**.
- **Visual Studio Code** with the **Jupyter** and **PostgreSQL** extensions installed.
- A **Python 3.11+** environment with the packages listed in [requirements.txt](requirements.txt):
  - Database connectivity: `psycopg[binary]`
  - LLM and agent framework: `openai`, `agent-framework`
  - Long-term memory: `mem0`
  - Notebook compatibility: `jupyter`, `ipywidgets`, `nest_asyncio`
  - Data validation: `pydantic`
  - HTTP: `requests`
  - Environment management: `python-dotenv`
  - UI: `gradio`

> **Note for lab attendees:** the provided lab VM already has Python, every package in [requirements.txt](requirements.txt), and all VS Code extensions pre-installed. You can jump straight to the notebooks.

## Lab Sections

The lab is delivered as two notebooks that build on each other.

### Notebook 1: Data Setup ([Code/1-data-setup.ipynb](Code/1-data-setup.ipynb))

1. **Connect to Azure HorizonDB** and enable the AI extensions (`vector`, `pg_diskann`, `pg_fts`, `age`, `azure_ai`).
1. **Load the case-law corpus** from [Dataset/cases.csv](Dataset/cases.csv) into a clean relational schema.
1. **Generate 1536-dim embeddings** for every opinion with Azure OpenAI and store them in a `vector(1536)` column.
1. **Build the retrieval indexes**: a BM25 index with `pg_fts`, and a DiskANN ANN index over the opinion vectors.
1. **Build the citation graph** with Apache AGE so each case becomes a `(:case)` node and every citation an edge.
1. **Register Azure OpenAI** with the `azure_ai` extension so later notebooks can call `azure_ai.extract(...)` directly from SQL.

By the end of Notebook 1 you have one Postgres database serving relational, vector, full-text, and graph queries with no separate stores.

### Notebook 2: Application Development ([Code/2-app-development.ipynb](Code/2-app-development.ipynb))

Each tool is introduced, smoke-tested by hand, and then handed to the agent so you can compare the raw output to the agent's narrative answer.

1. **Setup and configuration** (Part 3.1).
1. **Tool 1: `keyword_case_search`** (Part 3.2): BM25 full-text retrieval through `pg_fts`. Assemble your first single-tool agent.
1. **Tool 2: `semantic_case_search`** (Part 3.3): pgvector similarity search with DiskANN advanced filtering, then re-assemble the agent with two tools.
1. **Tool 3: `precedent_graph_search`** (Part 3.4): Cypher-style traversal of the AGE citation graph from BM25 + vector anchor cases. Re-assemble with three tools.
1. **Tool 4: `case_analyst_extract`** (Part 3.5): in-database extraction with `azure_ai.extract` to pull `holding`, `issues`, `statutes_cited`, `disposition` from full opinions. Re-assemble with four tools.
1. **Tool 5: `get_weather_evidence`** (Part 3.6): external evidence from Open-Meteo, used when a legal question turns on conditions like rainfall on a given date.
1. **Flagship run** (Part 3.7): all five tools registered together with a beefed-up system prompt, producing a real legal brief.
1. **Long-term memory with Mem0** (Part 3.8): wire Mem0 to pgvector in HorizonDB so the agent remembers client details and preferences across turns.
1. **Gradio web UI** (Part 3.9): wrap the full 5-tool + Mem0 agent in a Gradio chat app with a live Tool Trace panel and a Long-term Memory panel.

### Notebook 3: Diagnostics ([Code/3-diagnostics.ipynb](Code/3-diagnostics.ipynb))

Optional troubleshooting cells: verify connectivity, inspect extension state, re-check that embeddings, indexes, and the AGE graph are all in place.

## Getting Started

1. Open [Code/1-data-setup.ipynb](Code/1-data-setup.ipynb) in VS Code and work through every cell top to bottom. Each cell pairs a `🧠 Technical Background Notes` block with a `📝 Tasks` checklist so you always know what to look at.
1. Once Notebook 1 finishes successfully, open [Code/2-app-development.ipynb](Code/2-app-development.ipynb) and do the same.
1. In Part 3.9 (the last section of Notebook 2), running the final cell launches the Gradio UI on [http://localhost:7860](http://localhost:7860). Open it in a browser and chat with your finished agent.

## Additional Resources

- [Azure HorizonDB documentation](https://aka.ms/horizondb)
- [GraphRAG solution for Azure Database for PostgreSQL](https://aka.ms/pg-graphrag)
- [Graph data in Azure Database for PostgreSQL](https://aka.ms/age-blog)
- [PostgreSQL extension for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=ms-ossdata.vscode-postgresql)
- [Microsoft Agent Framework documentation](https://microsoft.github.io/agent-framework/)
- [Mem0 documentation](https://docs.mem0.ai/)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
