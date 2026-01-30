create database if not exists news_db;

use news_db;

create table if not exists sources (
    id int auto_increment primary key,
    name varchar(100) not null,
    url varchar(100) unique,
    reliability float default 1.0
);

create table if not exists news (
    id int auto_increment primary key,
    source_id int,
    title varchar(100) not null,
    summary text,
    url varchar(100),
    news_date timestamp
);

create table if not exists users (
    id int auto_increment primary key,
    username varchar(100) not null,
    interest_topics varchar(100)
);