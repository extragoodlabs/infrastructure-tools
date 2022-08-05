use lambda_http::request::RequestContext;
use lambda_http::{run, service_fn, Error, IntoResponse, Request, RequestExt, Response};
use log::LevelFilter;
use tokio_postgres::{Client, NoTls};
use serde::{Deserialize, Serialize};
use simple_logger::SimpleLogger;
use handlebars::Handlebars;
use std::collections::HashMap;
use std::env;

use handlebars::{ to_json };

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct Customer {
    customer_id: i32,
    first_name: String,
    last_name: String,
    email: Option<String>,
    active: i32
}

#[derive(Serialize, Deserialize)]
struct Pagination {
    page: i64,
    next: i64,
    prev: i64
}

async fn post_customer(event: Request, conn: Client) -> Result<Response<String>, Error> {
    let payload = match event.payload::<Customer>() {
        Ok(Some(customer)) => customer,
        _ => panic!("Can't create customer from input")
    };

    let insert = conn.execute(
        r"INSERT INTO customer (first_name, last_name, email, active, store_id, address_id) 
        VALUES ($1, $2, $3, $4, 1, 61)", 
        &[
            &payload.first_name,
            &payload.last_name,
            &payload.email,
            &payload.active,
        ]
    ).await?;

    log::info!(
        "Create CUSTOMER - Last generated key: {}",
        insert
    );

    let resp = Response::builder()
        .status(303)
        .header("Location", "/customers")
        .body(String::new())
        .map_err(Box::new)?;

    Ok(resp)
}

async fn get_single_customer(conn: Client, customer_id: String) -> Result<Vec<Customer>, Error> {
    log::info!("GET customers - by id {}", customer_id);

    let customers: Vec<Customer> = conn.query("SELECT customer_id, first_name, last_name, email, active FROM customer WHERE customer_id=$1", &[&customer_id])
    .await?
    .iter()
    .map(|row| 
        Customer {
            customer_id: row.get(0),
            first_name: row.get(1),
            last_name: row.get(2),
            email: row.get(3),
            active: row.get(4),
        }
    ).collect();

    Ok(customers)
}

async fn get_list_customers(conn: Client, page_num: i64) -> Result<Vec<Customer>, Error> {
    let offset: i64 = page_num * 10;
    log::info!("GET customers - list at offset {}", offset);

    let customers: Vec<Customer> = conn.query("SELECT customer_id, first_name, last_name, email, active FROM customer ORDER BY last_update desc LIMIT 10 OFFSET $1", &[&offset])
    .await?
    .iter()
    .map(|row| 
        Customer {
            customer_id: row.get(0),
            first_name: row.get(1),
            last_name: row.get(2),
            email: row.get(3),
            active: row.get(4),
        }
    ).collect();

    log::info!("Found {} customers", customers.len());
    match customers.first() {
        Some(first) => log::info!("Here's the first one: {:?}", first),
        _ => log::info!("Nothing to see")
    }
    
    Ok(customers)
}

async fn get_customers(event: Request, conn: Client) -> Result<Response<String>, Error> {
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

    let customers = match params.first("customer_id") {
        Some(customer_id) => get_single_customer(conn, customer_id.to_string()).await,
        _ => get_list_customers(conn, page_num).await,
    }?;

    let pagination = Pagination {
        page: page_num, 
        next: page_num + 1, 
        prev: page_num - 1
    };


    let mut data = HashMap::new();
    data.insert("customers", to_json(&customers));
    data.insert("pagination", to_json(&pagination));
    data.insert("showform", to_json(&showform));

    let mut handlebars = Handlebars::new();
    handlebars
        .register_template_string("customer", include_str!("../templates/customer.hbs"))
        .unwrap();

    let body = handlebars.render("customer", &data).unwrap();
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
        ("GET", "/customers") => get_customers(event, conn).await,
        ("POST", "/customers") => post_customer(event, conn).await,

        _ => panic!("Failed to match method and path"),
    }
}

/// This is the main body for the function.
/// Write your code inside it.
/// There are some code example in the following URLs:
/// <https://github.com/awslabs/aws-lambda-rust-runtime/tree/main/lambda-http/examples>
async fn function_handler(event: Request) -> Result<impl IntoResponse, Error> {
    log::debug!("Running in debug mode");

    let path = event.raw_http_path();

    let ctx = event.request_context();
    let method = match ctx {
        RequestContext::ApiGatewayV2(context) => context.http.method.to_string(),
        _ => "UNKNOWN".to_string(),
    };

    log::info!("Received {} request on {}", method, path);

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
    SimpleLogger::new().env().with_level(LevelFilter::Info).without_timestamps().init().unwrap();

    run(service_fn(function_handler)).await
}
