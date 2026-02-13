create database if not exists news_db;

use news_db;

drop table if exists user_reads;
drop table if exists user_interests;
drop table if exists news;
drop table if exists users;
drop table if exists topics;
drop table if exists sources;

-- news publishers
create table if not exists sources (
    id int auto_increment primary key,
    name varchar(100) not null,
    url varchar(255) unique,
    reliability float default 1.0
);

-- news categories
create table if not exists topics (
    id int auto_increment primary key,
    topic varchar(100) not null unique
);

-- news articles with topic mapping
create table if not exists news (
    id int auto_increment primary key,
    source_id int,
    topic_id int,
    title varchar(255) not null,
    summary text,
    url varchar(255),
    news_date timestamp default current_timestamp,
    foreign key (source_id) references sources(id) on delete cascade,
    foreign key (topic_id) references topics(id) on delete set null
);

-- user profiles
create table if not exists users (
    id int auto_increment primary key,
    username varchar(100) not null unique,
    created timestamp default current_timestamp
);

-- initial data/interests
create table if not exists user_interests(
    user_id int,
    topic_id int,
    primary key (user_id, topic_id),
    foreign key (user_id) references users(id) on delete cascade,
    foreign key (topic_id) references topics(id) on delete cascade
);

-- real time user activity logs for behavioral analysis
create table if not exists user_reads(
    id int auto_increment primary key,
    user_id int,
    news_id int,
    read_at timestamp default current_timestamp,
    foreign key (user_id) references users(id) on delete cascade,
    foreign key (news_id) references news(id) on delete cascade
);

insert ignore into topics (topic) values ('tech'), ('economy'), ('politics'), ('health'), ('sports'), ('entertainment'), ('science');
