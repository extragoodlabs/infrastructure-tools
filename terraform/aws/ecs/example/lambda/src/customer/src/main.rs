use lambda_http::request::RequestContext;
use lambda_http::{run, service_fn, Error, IntoResponse, Request, RequestExt, Response};
use log::LevelFilter;
use mysql::prelude::*;
use mysql::{params, Opts, Pool, PooledConn};
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
    active: bool
}

#[derive(Serialize, Deserialize)]
struct Pagination {
    page: i32,
    next: i32,
    prev: i32
}

fn post_customer(event: Request, mut conn: PooledConn) -> Result<Response<String>, Error> {
    let payload = match event.payload::<Customer>() {
        Ok(Some(customer)) => customer,
        _ => panic!("Can't create customer from input")
    };

    let _ = conn.exec_drop(
        r"INSERT INTO customer (first_name, last_name, email, active, store_id, address_id) 
        VALUES (:first_name, :last_name, :email, :active, 1, 61)", 
        params! {
            "first_name" => payload.first_name,
            "last_name" => payload.last_name,
            "email" => payload.email,
            "active" => payload.active,
        }
    )?;

    log::info!(
        "Create CUSTOMER - Last generated key: {}",
        conn.last_insert_id()
    );

    let resp = Response::builder()
        .status(303)
        .header("Location", "/customers")
        .body(String::new())
        .map_err(Box::new)?;

    Ok(resp)
}

fn get_single_customer(mut conn: PooledConn, customer_id: String) -> Result<Vec<Customer>, Error> {
    log::info!("GET customers - by id {}", customer_id);

    let customer = conn
        .exec_first(
            "SELECT customer_id, first_name, last_name, email, username, password FROM customer WHERE customer_id=:customer_id",
            params! {
                customer_id
            }
        ).map(|row|{
            row.map(|(customer_id, first_name, last_name, email, active)| Customer {
                customer_id,
                first_name,
                last_name,
                email,
                active,
            })
        })?
        .unwrap();

    Ok(vec![customer])
}

fn get_list_customers(mut conn: PooledConn, page_num: i32) -> Result<Vec<Customer>, Error> {
    let offset = page_num * 10;
    log::info!("GET customers - list at offset {}", offset);

    let customers = conn
        .exec_map(
            "SELECT customer_id, first_name, last_name, email, active FROM customer ORDER BY last_update desc LIMIT 10 OFFSET :offset",
            params! {
                offset
            },
            |(customer_id, first_name, last_name, email, active)| {
                Customer { customer_id, first_name, last_name, email, active }
            },
        )?;

    Ok(customers)
}

fn get_customers(event: Request, conn: PooledConn) -> Result<Response<String>, Error> {
    let params = event.query_string_parameters();

    let page_num = match params.first("page") {
        Some(num) if num.starts_with("-") => 0,
        Some(num) => num.parse::<i32>().unwrap_or(0),
        _ => 0,
    };

    let showform = match params.first("new") {
        Some("t") => true,
        _ => false,
    };

    let customers = match params.first("customer_id") {
        Some(customer_id) => get_single_customer(conn, customer_id.to_string()),
        _ => get_list_customers(conn, page_num),
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
    pool: PooledConn,
) -> Result<impl IntoResponse, Error> {
    let method_path = (method, path);
    match method_path {
        ("GET", "/customers") => get_customers(event, pool),
        ("POST", "/customers") => post_customer(event, pool),

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

    let url: String = env::var("MYSQL_URL").unwrap();
    let pool = Pool::new(Opts::from_url(&url)?)?;

    match pool.try_get_conn(1000) {
        Ok(conn) => router(&method, &path, event, conn).await,
        _ => panic!("Failed to connect to backend"),
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    SimpleLogger::new().env().with_level(LevelFilter::Info).without_timestamps().init().unwrap();

    run(service_fn(function_handler)).await
}
