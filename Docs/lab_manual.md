@lab.Title

Sign in to your VM with the following credentials:

**Username: ++@lab.VirtualMachine(Win11-Pro-Base-VM).Username++**

**Password: +++@lab.VirtualMachine(Win11-Pro-Base-VM).Password+++**

# Table of contents

1. [Part 0 - Sign in to Azure and explore Azure resources](#part-0---sign-in-to-azure-and-explore-azure-resources)
2. [Part 1 - Connect to your Azure HorizonDB database using VS Code Extension for PostgreSQL](#part-1---connect-to-your-azure-horizondb-database-using-vs-code-extension-for-postgresql)
    1. [Open VS Code and set up database connection to Azure PostgreSQL](#open-vs-code-and-set-up-database-connection-to-azure-postgresql)
    2. [Create Connection](#create-connection)
    3. [Explore VS Code Extension for PostgreSQL Dashboard](#explore-vs-code-extension-for-postgresql-dashboard)
    
3. [Part 2 and 3 - Data Setup and Agentic App Development](#part-2-and-3---data-setup-and-agentic-app-development)

===

# Part 0 - Sign in to Azure and explore Azure resources
In this section, we'll open Edge browser in the lab environment and sign in to the Azure portal to review the Azure resources we will use in this lab.

1. Double-select on the **Microsoft Azure Portal** icon on the desktop.

	!IMAGE[portal1.jpg](instructions310474/portal1.jpg)

1. On the sign in screen, enter the following credentials:

	!IMAGE[login1.jpg](instructions310474/login1.jpg)

    - Username: +++@lab.CloudPortalCredential(User1).Username+++
    - TAP: +++@lab.CloudPortalCredential(User1).TAP+++

	> **Note:** This lab uses a Temporary Access Pass (TAP) for the Azure subscription password.  If you need to access this TAP code again, use the **Resources** tab at the top of these lab instructions.
    
    !IMAGE[tap1.jpg](instructions310474/tap1.jpg)

<!-- > [!HELP]
>If you need to reset your Temporary Access Password (TAP), select this button:
>@lab.Activity(Automated1)
>
>TAP: +++@lab.Variable(tap)+++
> 
> **Note:** You will only be able to use this TAP after generating it, the other one will no longer work. -->

1. Once logged in to the Azure portal landing page, select **View all resources**.

	!IMAGE[view_all_res1.jpg](instructions310474/view_all_res1.jpg)

1. Observe the two Azure resources, we'll be using these during the course of this lab:
    - Azure OpenAI instance
    - Azure HorizonDB database instance

	!IMAGE[res-check.png](instructions342798/res-check.png)

===

# Part 1 - Connect to your Azure HorizonDB database using VS Code Extension for PostgreSQL

## Open VS Code and set up database connection to Azure PostgreSQL

1. Go to your desktop and double select the **VS Code** icon to open VS Code on your lab VM.

	!IMAGE[vs-code-icon.png](instructions342798/vs-code-icon.png)

1. Once inside VS Code, you should be already in the **"C:\\Lab"** folder.  If not, select **File** > **Open Folder...** > Choose **"C:\\Lab"** to open this folder into your workspace

	!IMAGE[lab-folder.png](instructions342798/lab-folder.png)

1. Now, in the **"LAB"** folder, look for a **".env"** file and double click to open it	

 	!IMAGE[env-file-click.png](instructions342798/env-file-click.png)

1. With the **".env"** file open, let's look at some of the variables defined.  This file contains all the credentials needed to connect to the Azure OpenAI and Azure HorizonDB instances that were deployed during the creation of this lab.  Most of these credentials we will not need to copy/paste as we will programmatically load them into our code notebook in a later step in this lab.

	But for the next couple steps, we will use the following values of these variables to copy/paste to make our connection to the HorizonDB database from within VS Code:

	- AZURE_PG_HOST
    - AZURE_PG_USER
    - AZURE_PG_PASSWORD

	!IMAGE[env-details.png](instructions342798/env-details.png)

1. In the next few steps, we are going to use the VS Code Extension for PostgreSQL to add a connection to our HorizonDB database. Leave the **".env"** file open, we will use it in the next few steps. On the left navigation, select the **elephant** icon.

	!IMAGE[ele-icon-1.png](instructions342798/ele-icon-1.png)

===

## Create Connection

1. Once the extension loads, in the **POSTGRESQL** panel select the **Add Connection** button.

	!IMAGE[vs-code-add-conn.png](instructions342798/vs-code-add-conn.png)

1. Fill out the connection form with the following values"

	- For **SERVER NAME**, copy/paste the **AZURE_PG_HOST** value from the `.env` file
        - Example: **horizondb-lab-australiaeast-czhpjspykdk4q.e557d0d51d1e.australiaeast.horizondb.azure.com**
    - For **AUTHENTICATION TYPE**, choose **Password** *(Note: Entra ID is coming soon for HorizonDB)*
    - For **USER NAME**, type **labUser**
    - For **PASSWORD**, copy/paste the **AZURE_PG_PASSWORD** value from the `.env` file
        - Example: **Zcohzrudys5q3e!**
    - For **DATABASE**, leave blank
    - For **CONNECTION NAME**, type **lab**

	!IMAGE[add-conn-screen.png](instructions342798/add-conn-screen.png)

1. Next, click **"Test Connection"**, and you should see a green check box appear.
	
    > **Note:** during the lab creation process we automatically allow-listed this VM's IP address to allow connections into your instance of HorizonDB. In the future, you will need to ensure you take this step to open access to connect to your HorizonDB database either directly with a query editor tool, or programmatically.

	!IMAGE[add-conn-test-conn.png](instructions342798/add-conn-test-conn.png)

1. Lastly, click **"Save & Connect"** to save the connection and open the connection to the HorizonDB database

	!IMAGE[save-and-connect.png](instructions342798/save-and-connect.png)

**Congratulations, you just signed in to your Azure HorizonDB database using the VS Code Extension for PostgreSQL!**

===

## Explore VS Code Extension for PostgreSQL Dashboard

1. Now that we have our connection created, let's explore the VS Code Extension for PostgreSQL and our HorizonDB database.  First, right-click on your **"lab"** connection we just created, and select the "Dashboard" option from the context menu:

	!IMAGE[select-dashboard.png](instructions342798/select-dashboard.png)

1. When the Dashboard loads, you will see it provides a robust set of performance details such as **wait events, disk i/o, transactions, storage, and more**.

	!IMAGE[dashboard-main.png](instructions342798/dashboard-main.png)

1. To continue exploring the VS Code Extension for PostgrSQL, now expand the **"Databases"** node under the **"lab"** connection.  Look for the **"postgres"** database, right-click it and select **"New Query"** from the context menu.

	!IMAGE[new-query.png](instructions342798/new-query.png)

1. Now run the following query by copying and pasting the following SQL block into the query editor window, then click the green play arrow on the top right to execute the SQL statement.  The purpose of this SQL query is just to illustrate the process of running queries and seeing results using the VS Code Extension for PostgreSQL.

	During the course of this lab most SQL queries will be ran programmatically via Python code and the pscyopg Python package.  However, there are a few queries you will need to run using the query editor in the VS Code Extension, so stay tuned for those!

	```SQL

    SELECT
    	current_database() AS database_name,
        current_user AS connected_user,
        now() AS server_time,
        version() AS postgres_version;
    ```

	!IMAGE[empty-query-example.png](instructions342798/empty-query-example.png)

===

# Part 2 and 3 - Data Setup and Agentic App Development

For the remainder of the lab we are going to work from two Jupyter Python Notebooks within VS Code.  All further lab instructions will be in-line within each notebook. The first notebook (Notebook 1) is a data setup notebook and the second notebook (Notebook 2) is the agentic application development notebook.

These notebooks are both located in the **"C:\\Lab"** folder structure under the folder **"Code"**:

- **1-data-setup.ipynb** (Notebook 1)
- **2-app-development.ipynb** (Notebook 2)

Additionally, there is a third, optional notebook, which is a diagnostics notebook for ensuring server settings and configurations:

- **3-diagnostics.ipynb** (Notebook 3)

## Open Notebook 1 - Data Setup

1. Within VS Code, on the left navigation bar, select the **Explorer** icon to return to the **Explorer** view.

	!IMAGE[files-icon.png](instructions342798/files-icon.png)

1. Expand the **Code** folder and look for a file name **1-data-setup.ipynb** (Notebook 1), then double-click the file.

	!IMAGE[notebook-1.png](instructions342798/notebook-1.png)

1. This will open the first notebook. Read each section of the notebook and follow the in-line instructions.

1. Once you complete Notebook 1, return to the **Code** folder and open the second notebook with the file name **2-app-development.ipynb** (Notebook 2).  Again, follow the in-line instructions and that will complete the lab.

	!IMAGE[notebook-2.png](instructions342798/notebook-2.png)
	
	>[!alert] At this point, continue the lab following the instructions in the Notebook 1 in VS Code.