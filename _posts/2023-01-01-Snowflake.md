---
title: Snowflake
author: tudeikb
date: 2023-01-01
category: Snowflake
layout: post
---


## Virtual Warehouses

### Overview

Snowflake warehouse size impacts **costs** and **query performance**. 

Snowflake warehouse is a **cluster of computational resources** used for running queries and tasks. It functions as an on-demand resource, separate from any data storage system, and is similar to a virtual machine (VM).

The number of nodes available for a query:

| warehouse size | number of nodes | cost |
|----------------|-----------------|------|
| XS             | 1               | x    |
| S              | 2               | x    |
| M              | 4               | x    |
| L              | 8               | x    |
| XL             | 16              | x    |
| 2XL            | 32              | x    |
| 3XL            | 64              | x    |
| 4XL            | 128             | x    |
| 5XL            | 256             | x    |
| 6XL            | 512             | x    |

> **Note:**
> Both the number of nodes and the cost **double** with each increase in warehouse size.
{: .block-warning }


### Choose The Right WH Size
Steps to effectively right-size the virtual warehouse:
1. **Start small and scale up as needed.** 

    Until you find the sweet spot of maximum performance at the lowest cost. 

    If the cost of running the warehouse doubles with each increase in size, then you would ideally want the query execution time to be at least halved to justify the increased cost from a performance standpoint. 🤔

    $\Rightarrow$ Choose the size that offers the best cost-to-performance ratio. 🤔

2. **Check if the warehouse is under or over provisioned.**

    An under-provisioned Snowflake warehouse may not have sufficient resources to handle the workload, leading to sluggish query performance and potential bottlenecks. To identify under-provisioning, monitor performance indicators such as **query execution time**, **queue time**, and **the number of queued queries**. If these metrics consistently show poor performance, increasing the warehouse size to allocate more resources may be necessary.

    An over-provisioned Snowflake warehouse may have more resources than required, resulting in unnecessary costs without providing any significant performance improvements. To identify over-provisioning, analyze the warehouse's resource utilization, such as **CPU** and **memory usage**. If these metrics consistently show low utilization, it may be more cost-effective to reduce the warehouse size.

3. **Monitor disk spillage.**
    It's crucial to monitor both local and remote disk spillage. In Snowflake, when a warehouse cannot fit an operation in memory, it starts spilling data first to the local disk of a warehouse node, and then to remote storage. This process, called disk spilling, leads to decreased performance and can be seen in the query profile as "Bytes spilled to local/remote storage." When the amount of spilled data is significant, it can cause noticeable degradation in warehouse performance.

---

### Monitor Credit Usage
Snowflake provides a comprehensive view of the credits consumed by virtual warehouses, aggregated on an hourly basis (```snowflake.account_usage.warehouse_metering_history```). This aggregation encompasses all queries executed within the hour, in addition to the costs associated with maintaining the warehouse and any other related cloud services.

#### Detailed Query Cost Analysis
To accurately determine the credit cost associated with specific queries, it is advisable to adopt a strategic approach. This involves setting up a dedicated virtual warehouse exclusively for executing the queries of interest. By isolating these queries, you can more precisely calculate their credit consumption.

#### Calculation Methodology
The credit usage for a particular query can be estimated by proportionally distributing the total credits consumed by the warehouse during the hour. The proportion is derived based on the query's execution time relative to the total runtime of the warehouse within that hour.

$$
\text{Credit Usage per Query} = \left( \frac{\text{Query Execution Time}}{\text{Total Warehouse Runtime}} \right) \times \text{Total Credits Consumed}
$$

#### Benefits
- **Precision:** This method allows for a more accurate allocation of costs to individual queries, providing clear insights into their resource consumption.
- **Optimization:** Understanding the credit usage at the query level enables targeted optimization efforts, potentially leading to cost savings.
- **Transparency:** It fosters transparency in resource utilization, helping stakeholders to better comprehend the financial implications of query execution.

#### Sample queries
> **Warning:**
>
> `snowflake.account_usage.query_history`: Latency for the view may be up to 45 minutes
> `snowflake.account_usage.task_history`: Latency for the view may be up to 45 minutes
> `snowflake.account_usage.graph_versions`: Latency up to 3 hours
> `snowflake.account_usage.warehouse_metering_history`: New records show on every hour (hourly aggregate)
{: .block-warning }

1. Find the DAG run_id:
    - After running the DAG go to: Activity > Task History
    - Select graph run
    - Little button on the right: Open underlying SQL query in worksheet

    ```sql
    -- Auto-generated timeline query:
    SELECT
    name,
    schema_name,
    database_name,
    CONVERT_TIMEZONE('UTC', QUERY_START_TIME) as query_start_time,
    CONVERT_TIMEZONE('UTC', COMPLETED_TIME) as completed_time,
    CONVERT_TIMEZONE('UTC', SCHEDULED_TIME) as scheduled_time,
    DATEDIFF('millisecond', QUERY_START_TIME, COMPLETED_TIME) as duration,
    state,
    error_code,
    error_message,
    query_id,
    graph_version,
    0 as attempt_number,
    run_id
    FROM
    table(
        <database_name>.information_schema.task_history(
        RESULT_LIMIT => 1000,
        ROOT_TASK_ID => <root_task_id>,
        SCHEDULED_TIME_RANGE_START => TO_TIMESTAMP_LTZ('2023-10-25T11:10:35.156Z', 'AUTO'),
        SCHEDULED_TIME_RANGE_END => TO_TIMESTAMP_LTZ('2023-10-25T13:06:07.164Z', 'AUTO')
        )
    )
    WHERE
    run_id = <run_id>
    ORDER BY
    query_start_time ASC
    LIMIT
    250;
    ```

    ```sql
    -- Alternatively search for the latest complete task graph:
    select * from snowflake.account_usage.complete_task_graphs
    where state = 'SUCCEEDED'
    order by query_start_time desc;
    ```

2. Calculate various metrics using the retrieved DAG `run_id`.

    ```sql
    -- Details of the queries executed by the task graph run
    -- (does not include queries ran inside stored procedures)
    select
        m.start_time as warehouse_metering_start,
        m.end_time as warehouse_metering_end,
        q.query_id,
        q.query_text,
        q.query_type,
        q.warehouse_size,
        q.warehouse_name,
        q.compilation_time,
        q.execution_time,
        q.total_elapsed_time,
        q.bytes_scanned,
        q.bytes_written,
        q.bytes_spilled_to_local_storage,
        q.bytes_spilled_to_remote_storage,
        q.bytes_sent_over_the_network,
        q.rows_produced,
        q.rows_inserted,
        q.rows_updated,
        q.rows_deleted,
        q.partitions_scanned,
        q.partitions_total,
        --q.credits_used_cloud_services as q_credits_used_cloud_services, -- too much detail
        zeroifnull(sum(q.total_elapsed_time / 1000) over (partition by q.warehouse_name, warehouse_metering_start)) as warehouse_execution_time,
        zeroifnull(m.credits_used) as warehouse_credits_used,
        zeroifnull(total_elapsed_time / 1000 / nullif(warehouse_execution_time, 0)) as query_percentage_warehouse,
        query_percentage_warehouse * warehouse_credits_used as query_warehouse_credits_used
        --m.credits_used_cloud_services as m_credits_used_cloud_services, -- too much detail
        --m.credits_used_compute as m_credits_used_compute, -- too much detail
        --m.credits_used as m_credits_used -- equal to sum of m_credits_used_cloud_services and m_credits_used_compute, also equal to warehouse_credits_used
    from snowflake.account_usage.query_history q
    left join snowflake.account_usage.warehouse_metering_history m
    on m.warehouse_name = q.warehouse_name
        and q.start_time between m.start_time and m.end_time
    where q.query_id in (
        select query_id
        from snowflake.account_usage.task_history
        where run_id = <run_id>)
    order by q.start_time desc
    ;
    ```

    ```sql
    -- Details of the queries executed by the task graph run
    -- (including queries ran inside stored procedures)
    select
        m.start_time as warehouse_metering_start,
        m.end_time as warehouse_metering_end,
        q.query_id,
        q.query_text,
        q.query_type,
        q.warehouse_size,
        q.warehouse_name,
        q.compilation_time,
        q.execution_time,
        q.total_elapsed_time,
        q.bytes_scanned,
        q.bytes_written,
        q.bytes_spilled_to_local_storage,
        q.bytes_spilled_to_remote_storage,
        q.bytes_sent_over_the_network,
        q.rows_produced,
        q.rows_inserted,
        q.rows_updated,
        q.rows_deleted,
        q.partitions_scanned,
        q.partitions_total,
        --q.credits_used_cloud_services as q_credits_used_cloud_services, -- too much detail
        zeroifnull(sum(q.total_elapsed_time / 1000) over (partition by q.warehouse_name, warehouse_metering_start)) as warehouse_execution_time,
        zeroifnull(m.credits_used) as warehouse_credits_used,
        zeroifnull(total_elapsed_time / 1000 / nullif(warehouse_execution_time, 0)) as query_percentage_warehouse,
        query_percentage_warehouse * warehouse_credits_used as query_warehouse_credits_used
        --m.credits_used_cloud_services as m_credits_used_cloud_services, -- too much detail
        --m.credits_used_compute as m_credits_used_compute, -- too much detail
        --m.credits_used as m_credits_used -- equal to sum of m_credits_used_cloud_services and m_credits_used_compute, also equal to warehouse_credits_used
    from snowflake.account_usage.query_history q
    left join snowflake.account_usage.warehouse_metering_history m
    on m.warehouse_name = q.warehouse_name
        and q.start_time between m.start_time and m.end_time
    where q.session_id in (
        select session_id
        from snowflake.account_usage.query_history
        where query_id in (
            select query_id
            from snowflake.account_usage.task_history
            where run_id = <run_id>
            )
        )
        and query_type != 'CALL' -- exclude, otherwise this will duplicate some info
    order by q.start_time desc
    ;
    ```

    ```sql
    -- Workflow totals - compute sums
    select
        sum(q.compilation_time) as sum_compilation_time,
        sum(q.execution_time) as sum_execution_time,
        sum(q.total_elapsed_time) as sum_total_elapsed_time,
        sum(q.bytes_scanned) as sum_bytes_scanned,
        sum(q.bytes_written) as sum_bytes_written,
        sum(q.bytes_spilled_to_local_storage) as sum_bytes_spilled_to_local_storage,
        sum(q.bytes_spilled_to_remote_storage) as sum_bytes_spilled_to_remote_storage,
        sum(q.bytes_sent_over_the_network) as sum_bytes_sent_over_the_network,
        sum(q.rows_produced) as sum_rows_produced,
        sum(q.rows_inserted) as sum_rows_inserted,
        sum(q.rows_updated) as sum_rows_updated,
        sum(q.rows_deleted) as sum_rows_deleted,
        sum(q.partitions_scanned) as sum_partitions_scanned,
        sum(q.partitions_total) as sum_partitions_total
    from snowflake.account_usage.query_history q
    where q.session_id in (
        select session_id
        from snowflake.account_usage.query_history
        where query_id in (
            select query_id
            from snowflake.account_usage.task_history
            where run_id = <run_id>
            )
        )
        and query_type != 'CALL' -- exclude, otherwise this will duplicate some info
    ;
    ```

---
## Snowflake and GCS

### COPY INTO (unload) from Snowflake to GCS

```sql
copy into @<my_database_name>.<my_schema_name>.<my_stage_name>/gcs_folder_name/
from (
    select
    col1, col2, col3
    from <my_database_name>.<my_schema_name>.<my_table_name>
    );
```

```sql
copy into @<my_database_name>.<my_schema_name>.<my_stage_name>/gcs_folder_name/file_name.parquet
from (
    select
        *
    from
        <my_database_name>.<my_schema_name>.<my_table_name> 
        limit 100
    )
    file_format = (format_name = <my_database_name>.<my_schema_name>.<my_format_name>)
    --compression = snappy    <= not needed if already specified in the definition of 'my_format_name'
    overwrite = true
    header = true
    max_file_size = 2147483648
    ;
```