@lab.Title

Sign in to your VM with the following credentials:

**Username: ++@lab.VirtualMachine(Win11-Pro-Base-VM).Username++**

**Password: +++@lab.VirtualMachine(Win11-Pro-Base-VM).Password+++**

# Table of contents

1. [Part 0 - Sign in to Azure and explore Azure resources](#part-0---sign-in-to-azure-and-explore-azure-resources)
2. [Part 1 - Connect to your Azure HorizonDB database using the VS Code extension for PostgreSQL](#part-1---connect-to-your-azure-horizondb-database-using-the-vs-code-extension-for-postgresql)
    1. [Open VS Code and set up a database connection](#open-vs-code-and-set-up-a-database-connection)
    2. [Create a connection](#create-a-connection)
    3. [Explore the PostgreSQL extension dashboard](#explore-the-postgresql-extension-dashboard)
    
3. [Part 2 and 3 - Data setup and agentic app development](#part-2-and-3---data-setup-and-agentic-app-development)

===

# Part 0 - Sign in to Azure and explore Azure resources
In this section, you'll open the Edge browser in the lab environment and sign in to the Azure portal to review the resources you'll use in this lab.

1. Double-select the **Microsoft Azure Portal** icon on the desktop.

	!IMAGE[portal1.jpg](instructions310474/portal1.jpg)

1. On the sign-in screen, enter the following credentials:

	!IMAGE[login1.jpg](instructions310474/login1.jpg)

    - Username: +++@lab.CloudPortalCredential(User1).Username+++
    - TAP: +++@lab.CloudPortalCredential(User1).TAP+++

	> **Note:** This lab uses a Temporary Access Pass (TAP) for the Azure subscription password. If you need to access this TAP code again, use the **Resources** tab at the top of these lab instructions.
    
    !IMAGE[tap1.jpg](instructions310474/tap1.jpg)

<!-- > [!HELP]
>If you need to reset your Temporary Access Password (TAP), select this button:
>@lab.Activity(Automated1)
>
>TAP: +++@lab.Variable(tap)+++
> 
> **Note:** You will only be able to use this TAP after generating it, the other one will no longer work. -->

1. After you sign in to the Azure portal landing page, select **View all resources**.

	!IMAGE[view_all_res1.jpg](instructions310474/view_all_res1.jpg)

1. Observe the two Azure resources you'll use during this lab:
    - Azure OpenAI instance
    - Azure HorizonDB database instance

	!IMAGE[res-check.png](instructions342798/res-check.png)

===

# Part 1 - Connect to your Azure HorizonDB database using the Visual Studio Code extension for PostgreSQL

## Open Visual Studio Code and set up a database connection

1. On your desktop, double-select the **VS Code** icon to open VS Code on your lab VM.

	!IMAGE[vs-code-icon.png](instructions342798/vs-code-icon.png)

1. In VS Code, confirm you're in the **C:\\Lab** folder. If not, select **File** > **Open Folder** > **C:\\Lab** to open this folder in your workspace.

	!IMAGE[lab-folder.png](instructions342798/lab-folder.png)

1. In the **LAB** folder, find the **.env** file and double-select it to open it.

	!IMAGE[env-file-click.png](instructions342798/env-file-click.png)

1. Review the variables defined in the **.env** file. This file contains all the credentials needed to connect to Azure OpenAI and Azure HorizonDB instances deployed for this lab. A later step loads most credentials programmatically into the code notebook.

	For the next few steps, copy and paste these variable values to connect to the HorizonDB database from VS Code:

	- AZURE_PG_HOST
    - AZURE_PG_USER
    - AZURE_PG_PASSWORD

	!IMAGE[env-details.png](instructions342798/env-details.png)

1. Next, you'll use the VS Code extension for PostgreSQL to add a connection to your HorizonDB database. Leave the **.env** file open. On the left navigation, select the **elephant** icon.

	!IMAGE[ele-icon-1.png](instructions342798/ele-icon-1.png)

===

## Create a connection

1. After the extension loads, in the **POSTGRESQL** panel, select the **Add Connection** button.

	!IMAGE[vs-code-add-conn.png](instructions342798/vs-code-add-conn.png)

1. Fill out the connection form with the following values:

	- For **SERVER NAME**, copy and paste the **AZURE_PG_HOST** value from the `.env` file
        - Example: **horizondb-lab-australiaeast-czhpjspykdk4q.e557d0d51d1e.australiaeast.horizondb.azure.com**
    - For **AUTHENTICATION TYPE**, choose **Password** *(Note: Entra ID is coming soon for HorizonDB)*
    - For **USER NAME**, type **labUser**
    - For **PASSWORD**, copy and paste the **AZURE_PG_PASSWORD** value from the `.env` file
        - Example: **Zcohzrudys5q3e!**
    - For **DATABASE**, leave blank
    - For **CONNECTION NAME**, type **lab**

	!IMAGE[add-conn-screen.png](instructions342798/add-conn-screen.png)

1. Select **Test Connection**. A green check box appears when the connection succeeds.
	
    > **Note:** During lab creation, the VM's IP address was automatically added to the allow list for your HorizonDB instance. In the future, ensure you open access to connect to your HorizonDB database either directly with a query editor tool or programmatically.

	!IMAGE[add-conn-test-conn.png](instructions342798/add-conn-test-conn.png)

1. Select **Save & Connect** to save the connection and connect to the HorizonDB database.

	!IMAGE[save-and-connect.png](instructions342798/save-and-connect.png)

You've successfully connected to your Azure HorizonDB database using the VS Code extension for PostgreSQL.

===

## Explore the PostgreSQL extension dashboard

1. Now that you've created the connection, right-select your **lab** connection and choose **Dashboard** from the context menu.

	!IMAGE[select-dashboard.png](instructions342798/select-dashboard.png)

1. The Dashboard provides performance details such as wait events, disk I/O, transactions, storage, and more.

	!IMAGE[dashboard-main.png](instructions342798/dashboard-main.png)

1. To continue exploring, expand the **Databases** node under the **lab** connection. Find the **Postgres** database, right-select it, and choose **New Query** from the context menu.

	!IMAGE[new-query.png](instructions342798/new-query.png)

1. Copy and paste the following SQL into the query editor window, then select the green play arrow at the top right to run the statement. This query illustrates running queries and viewing results in the VS Code extension for PostgreSQL.

	During this lab, most SQL queries run programmatically via Python and the psycopg package. However, you'll run a few queries using the query editor in the VS Code extension—stay tuned for those.

	```SQL

    SELECT
    	current_database() AS database_name,
        current_user AS connected_user,
        now() AS server_time,
        version() AS postgres_version;
    ```

	!IMAGE[empty-query-example.png](instructions342798/empty-query-example.png)

===

# Part 2 and 3 - Data setup and agentic app development

For the remainder of the lab, you'll work from two Jupyter Python notebooks in VS Code. All further instructions are inline within each notebook. Notebook 1 covers data setup, and Notebook 2 covers agentic application development.

Both notebooks are in the **C:\\Lab** folder under the **Code** subfolder:

- **1-data-setup.ipynb** (Notebook 1)
- **2-app-development.ipynb** (Notebook 2)

A third, optional notebook provides diagnostics for server settings and configurations:

- **3-diagnostics.ipynb** (Notebook 3)

## Open Notebook 1 - data setup

1. In VS Code, on the left navigation bar, select the **Explorer** icon to return to the Explorer view.

	!IMAGE[files-icon.png](instructions342798/files-icon.png)

1. Expand the **Code** folder and double-select **1-data-setup.ipynb** (Notebook 1).

	!IMAGE[notebook-1.png](instructions342798/notebook-1.png)

1. Read each section of the notebook and follow the inline instructions.

1. After you complete Notebook 1, return to the **Code** folder and open **2-app-development.ipynb** (Notebook 2). Follow the inline instructions to complete the lab.

	!IMAGE[notebook-2.png](instructions342798/notebook-2.png)
	
	>[!alert] At this point, continue the lab following the instructions in Notebook 1 in VS Code.
