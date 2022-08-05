use tracing::{event, Level};
use lambda_http::request::RequestContext;
use lambda_http::{run, service_fn, Error, IntoResponse, Request, RequestExt, Response};
use tokio_postgres::{Client, NoTls};
use serde::{Deserialize, Serialize};
use handlebars::Handlebars;
use std::collections::HashMap;
use std::env;

use handlebars::{ to_json };

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct Staff {
    staff_id: i32,
    first_name: Option<String>,
    last_name: Option<String>,
    email: Option<String>,
    username: Option<String>,
    password: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct Pagination {
    page: i64,
    next: i64,
    prev: i64
}


async fn post_staff(event: Request, conn: Client) -> Result<Response<String>, Error> {
    let payload = match event.payload::<Staff>() {
        Ok(Some(staff)) => staff,
        _ => panic!("Can't create staff from input")
    };

    let insert = conn.execute(
        r"INSERT INTO staff (first_name, last_name, email, username, password, store_id, address_id) 
        VALUES ($1, $2, $3, $4, $5, 1, 61)", 
        &[
            &payload.first_name,
            &payload.last_name,
            &payload.email,
            &payload.username,
            &payload.password
        ]
    ).await?;

    event!(Level::INFO, "Create STAFF - Last generated key: {}",
        insert);

    let resp = Response::builder()
        .status(303)
        .header("Location", "/staff")
        .body(String::new())
        .map_err(Box::new)?;

    Ok(resp)
}

async fn get_single_staff(conn: Client, staff_id: String) -> Result<Vec<Staff>, Error> {
    event!(Level::INFO, "GET STAFF - by id: {}",
        staff_id);

    let staff: Vec<Staff> = conn.query("SELECT staff_id, first_name, last_name, email, username, password FROM staff WHERE staff_id=$1", &[&staff_id])
    .await?
    .iter()
    .map(|row| 
        Staff {
            staff_id: row.get(0),
            first_name: row.get(1),
            last_name: row.get(2),
            email: row.get(3),
            username: row.get(4),
            password: row.get(5),
        }
    ).collect();

    Ok(staff)
}

async fn get_list_staff(conn: Client, page_num: i64) -> Result<Vec<Staff>, Error> {
    let offset = page_num * 10;
    event!(Level::INFO, "GET list of staff - at offset: {}",
        offset);

    let staff: Vec<Staff> = conn.query("SELECT staff_id, first_name, last_name, email, username, password FROM staff ORDER BY last_update desc LIMIT 10 OFFSET $1", &[&offset])
    .await?
    .iter()
    .map(|row| 
        Staff {
            staff_id: row.get(0),
            first_name: row.get(1),
            last_name: row.get(2),
            email: row.get(3),
            username: row.get(4),
            password: row.get(5),
        }
    ).collect();

    Ok(staff)
}

async fn get_staff(event: Request, conn: Client) -> Result<Response<String>, Error> {
    let params = event.query_string_parameters();

    let page_num = match params.first("page") {
        Some(num) if num.starts_with("-") => 0,
        Some(num) => num.parse::<i64>().unwrap_or(0),
        _ => 0,
    };

    let showform = match params.first("new") {
        Some("t") => true,
        _ => false,
    };

    let staff = match params.first("staff_id") {
        Some(staff_id) => get_single_staff(conn, staff_id.to_string()).await,
        _ => get_list_staff(conn, page_num).await,
    }?;

    let pagination = Pagination {
        page: page_num,
        next: page_num + 1,
        prev: page_num - 1
    };

    // Return something that implements IntoResponse.
    // It will be serialized to the right response event automatically by the runtime
    // let body = serde_json::to_string(&staff).unwrap();

    let mut data = HashMap::new();
    data.insert("staff", to_json(&staff));
    data.insert("pagination", to_json(&pagination));
    data.insert("showform", to_json(&showform));

    let mut handlebars = Handlebars::new();
    handlebars
        .register_template_string("staff", include_str!("../templates/staff.hbs"))
        .unwrap();

    let body = handlebars.render("staff", &data).unwrap();
    let resp = Response::builder()
        .status(200)
        .header("content-type", "text/html")
        .body(body)
        .map_err(Box::new)?;

    Ok(resp)
}

async fn router(
    method: &str,
    path: &str,
    event: Request,
    conn: Client,
) -> Result<impl IntoResponse, Error> {
    let method_path = (method, path);
    match method_path {
        ("GET", "/staff") => get_staff(event, conn).await,
        ("POST", "/staff") => post_staff(event, conn).await,

        _ => panic!("Failed to match method and path"),
    }
}

/// This is the main body for the function.
/// Write your code inside it.
/// There are some code example in the following URLs:
/// <https://github.com/awslabs/aws-lambda-rust-runtime/tree/main/lambda-http/examples>
async fn function_handler(event: Request) -> Result<impl IntoResponse, Error> {
    let path = event.raw_http_path();

    let ctx = event.request_context();
    let method = match ctx {
        RequestContext::ApiGatewayV2(context) => context.http.method.to_string(),
        _ => "UNKNOWN".to_string(),
    };

    event!(Level::INFO, "Received {} request on {}", method, path);

    let url: String = env::var("POSTGRESQL_URL").unwrap();
    let (client, connection) =
        tokio_postgres::connect(&url, NoTls).await?;

    // The connection object performs the actual communication with the database,
    // so spawn it off to run on its own.
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            eprintln!("connection error: {}", e);
        }
    });
    
    return router(&method, &path, event, client).await;
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        // disabling time is handy because CloudWatch will add the ingestion time.
        .without_time()
        .init();

    run(service_fn(function_handler)).await
}
