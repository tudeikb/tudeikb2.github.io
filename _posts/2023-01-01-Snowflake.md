---
title: Snowflake
author: tudeikb
date: 2023-01-01
category: Snowflake
layout: post
---

## COPY INTO (unload) from Snowflake to GCS

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