/**
* Name: raycasting
* Based on the internal empty template. 
* Author: baptiste
* Tags: 
*/


model raycasting

/* Insert your model definition here */

global {
	
	//player events
	bool catch_mouse;
	string direction_asked <- "None" among:["None", "Left", "Right", "Front", "Back"];
	float asked_heading;
	
	// game life cycle
	float last_frame_time;
	list<float> fps;
	
	// world dimensions
	int nb_cells_width	<- 20;
	int nb_cells_height <- 20;
	float cell_width 	<- world.shape.width/nb_cells_width;
	float cell_height	<- world.shape.height/nb_cells_height;
	
	init {
		
		last_frame_time <- machine_time#ms;
		create player;
		create baddy number:10;
		
	}
	reflex game_loop {
		float current <- machine_time#ms;
		float delta <- current - last_frame_time + 0.00001;// adding epsilon to cancel divisions by zero
		
		do game_loop(delta);
	
		last_frame_time <- current;
		fps <+ 1/delta;
		if length(fps) > 10 {
			remove from:fps index:0;
		}
	}
	
	
	action game_loop(float delta){

		// refresh heading
		do mouse_move;
		
		// process movement
		ask player{
			heading <- asked_heading;
			do process_movement(delta);
			do update_rays;
		}
		
	}
	
	action arrow_up {
		direction_asked <- "Front";
	}
	action arrow_down {
		direction_asked <- "Back";
	}
	action arrow_left {
		direction_asked <- "Left";
	}
	action arrow_right {
		direction_asked <- "Right";
	}
	
	action mouse_move {
		if catch_mouse {
			ask player {
				let pt <- #user_location - location;
				asked_heading <- atan2(pt.y,pt.x);
			}			
		}
	}
	
	action mouse_down {
		
	}
	
	action mouse_enter {
		catch_mouse <- true;
	}
	
	action mouse_exit {
		catch_mouse <- false;
	}
	
}


// The game map
grid game_map width:nb_cells_width height:nb_cells_height{

	string type <- "floor" among:["floor", "wall"];
	list<baddy> enemies <- [] update:baddy overlapping self;
	
	init {
		type <- rnd_choice(map(["floor"::0.8, "wall"::0.2]));
		if type = "wall" {
			color <- #red;
		}
		else {
			color <- #grey;
		}
	}
	

}

species baddy {
	float heading;
	geometry shape <- rectangle(1,1);
	rgb color <- #red;
	
	init {
		loop while:(game_map overlapping (shape at_location location)) one_matches (each.type = "wall"){
			location <- any_location_in(world.shape);
		}
	}
}


species player {
	
	// movement 
	float speed <- 20#km/#h;
	float heading;
	geometry shape <- circle(1);
	
	// field of view
	list<geometry> rays <- list_with(nb_rays, nil);
	list<pair<int,float>> walls;
	list<point> enemies;
	
	init {
		loop while:(game_map overlapping (shape at_location location)) one_matches (each.type = "wall"){
			location <- any_location_in(world.shape);
		}
	}
	
	reflex update_heading {
		let loc <- #user_location - location;
		heading <- atan2(loc.y, loc.x);
	}
	
	// constants for raycasting algorithm
	float FOV <- 150.0;
	float half_FOV <- FOV/2;
	int nb_rays <- 100;
	float step_angle <- FOV/nb_rays;
	float scale <- world.shape.width/2/nb_rays;
	float max_depth <- 100#m;
	float depth_inc <- 1#m;
	float epsilon <- 0.0001;
	list<geometry> points;
	
	// fills the rays list with all the rays of the fov of the player
	action update_rays {
	
		let ox <- location.x;
		let oy <- location.y;
		let x_map <- int(location.x/cell_width)*cell_width;
		let y_map <- int(location.y/cell_height)*cell_height;
		//write "map " + x_map + " " + y_map + " coord" + ox + " " +oy ;
		
//		rays <- list_with(nb_rays, nil); //todo remove for optimisation
		walls <- [];
		let ray_angle <- heading - half_FOV;
		loop ray from:0 to: nb_rays-1 {
			let sin_a <- sin(ray_angle);
			let cos_a <- cos(ray_angle);
			//write ray_angle;
			float depth_vert;
			float depth_hor;
			
			// ==========================================
			// looking for intersection on vertical lines
			// ==========================================
			
			// cos_a = 0 means we are looking straight downward/upwards so vertical line collision cannot happen	
			float x_vert;
			float y_vert;
			if cos_a != 0 {
				
				float dx;
				// if we are looking towards the right side, we start on the next vertical line
				if cos_a > 0 { 
					dx 		<- cell_width;
					x_vert 	<- x_map + dx;
				}
				// if we are looking towards the left side we increment in the opposite direction
				else {
					// minus epsilon so we are just a bit left of the vertical line to hit the wall on the left
					x_vert <- x_map - epsilon; 
					dx <- -cell_width;
				}
				
				depth_vert <- (x_vert - ox)/cos_a;
				y_vert <- oy + depth_vert * sin_a;
				
				float delta_depth <- dx/cos_a;
				float dy <- delta_depth * sin_a;
				
				loop i from:0 to:int(sqrt(nb_cells_width*nb_cells_width + nb_cells_height*nb_cells_height))-1 {
					int x <- int(int(x_vert)/cell_width);
	    			int y <- int(int(y_vert)/cell_height);
	    			//write "test " + x + " " + y;
	    			// if we are out of map or touched a wall it's over
	    			if x < 0 or x >= nb_cells_width or y < 0 or y >= nb_cells_height{
	            		//write "reached border " + x_vert + " " + y_vert; 
	            		//rays[ray] <- line(location,  {x_vert, y_vert});
	            		//points <- points + p;
	    				break;
	    			} 
	    			else {
	    				loop enemy over:game_map[x,y].enemies {
	    					
	    				}
	    				if game_map[x,y].type = "wall"{
//		            		rays[ray] <- line(location,  {x_vert, y_vert});
//		            		walls <+ pair(ray, depth_vert);
							//write "wall " + x_vert + " " + y_vert; 
			                break;
		            	}
		            }
					
					x_vert <- x_vert + dx;
					y_vert <- y_vert + dy;
				}
			}
			
			// ==========================================
			// looking for intersection on horizontal lines
			// ==========================================
			
			// sin_a = 0 means we are looking straight right/left so horizontal line collision cannot happen
			float x_hor;
			float y_hor;
			if sin_a != 0 {
				
				float dy;
				
				if sin_a > 0 { 
					// minus epsilon so we are just a bit above of the horizontal line to hit the wall on the top
					dy 		<- cell_height;
					y_hor 	<- y_map  + dy;
				}
				// if we are looking towards the bottom, we start on the next horizontal line
				else {
					dy <- -cell_height;
					y_hor <- y_map - epsilon; 
				}
				
				depth_hor <- (y_hor - oy)/sin_a;
				x_hor <- ox + depth_hor * cos_a;
				
				float delta_depth <- dy/sin_a;
				float dx <- delta_depth * cos_a;
				loop i from:0 to:int(sqrt(nb_cells_width*nb_cells_width + nb_cells_height*nb_cells_height))-1 {
					int x <- int(int(x_hor)/cell_width);
	    			int y <- int(int(y_hor)/cell_height);
	    			//write "test " + x + " " + y;	    			
	    			// if we are out of map or touched a wall it's over
	    			if x < 0 or x >= nb_cells_width or y < 0 or y >= nb_cells_height{
	            		//write "reached border " + x_vert + " " + y_vert; 
	            		rays[ray] <- line(location,  {x_hor, y_hor});
//	            		points <- points + p;
	    				break;
	    			} 
	    			else {
	    				loop enemy over:game_map[x,y].enemies {
	    					
	    				}
	    				if game_map[x,y].type = "wall"{
							//write "wall " + x_vert + " " + y_vert; 
//							rays[ray] <- line(location,  {x_hor, y_hor});
//	            			points <- points + p;
			                break;
		            	}
		            }
					
					x_hor <- x_hor + dx;
					y_hor <- y_hor + dy;
				}
			}
			
			// we check which one of the vert or hor is the shortest 
			point hor 	<- {x_hor, y_hor};
			let vert	<- {x_vert, y_vert};
			point best;
			if location distance_to hor < location distance_to vert {
				best <- hor;
			}
			else {
				best <- vert;
			}
			rays[ray] <- line(location, best);
    		walls <+ pair(ray, location distance_to best);
			
			ray_angle <- ray_angle + step_angle;
		}
	
	}
	
	
	
	action process_movement(float delta) {
		
		float dx <- 0.0;
		float dy <- 0.0;
		let adjusted_speed <- delta * speed;

		// processing the correct dx/dy in function of the direction asked			
		switch direction_asked {
			match "Front" {
				dx <- adjusted_speed * cos(heading);
				dy <- adjusted_speed * sin(heading);
			}
			match "Left" {
				dx <- adjusted_speed * sin(heading);
				dy <- -adjusted_speed * cos(heading);	
			}
			match "Back" {
				dx <- -adjusted_speed * cos(heading);
				dy <- -adjusted_speed * sin(heading);
			}
			match "Right" {
				dx <- -adjusted_speed * sin(heading);
				dy <- adjusted_speed * cos(heading);				
			}
		}
		
		let x <- location.x + dx;
		let y <- location.y + dy;
		//if we don't collide with a wall or get out of bound we move
		if 		x between(0, world.shape.width) 
			and y between(0, world.shape.height) 
			and game_map[int(x/cell_width), int(y/cell_height)].type != "wall" {
			location <- {x, y};
		}
		direction_asked <- "None";
	}
	
	
	aspect default {
		draw shape color:#blue;
		loop ray over:rays {
			draw ray color:#green;		
		}
		loop p over:points {
			draw p color:#brown;
		}
		
		draw line(location, {location.x + 3 * cos(heading), location.y + 3 * sin(heading)}) color:#yellow width:3;
	}
	
	aspect eye_of_the_beholder {
		// draw floor
		draw rectangle(world.shape.width, world.shape.height/2) at:{0, world.shape.height/2}+{world.shape.width/2,world.shape.height/4} color:#green;
		
		// draw ceiling
		draw rectangle(world.shape.width, world.shape.height/2) at:{0, world.shape.height/2}-{-world.shape.width/2,world.shape.height/4} color:#blue;
		
		// draw obstacles
		let wall_base_height <- world.shape.height;
		let wall_half_height <- wall_base_height/2;
		let wall_width <- world.shape.width/nb_rays;
		loop wall over:walls {
			float x_start <- wall.key * wall_width;
			float half_height <- wall_half_height/wall.value;
			draw rectangle(
				{x_start,max(world.shape.height/2-half_height, 0)},
				{x_start+wall_width,min(world.shape.height/2+half_height,world.shape.height)}
			) color:#brown;
		}
	}
}

experiment test autorun:true{
	
	
	action up{
		ask simulation {do arrow_up;}
	}
	action down{
		ask simulation {do arrow_down;}
	}
	action left{
		ask simulation {do arrow_left;}
	}
	action right{
		ask simulation {do arrow_right;}
	}
	action mouse_down{
		ask simulation {do mouse_down;}
	}
	action mouse_enter{
		ask simulation {do mouse_enter;}
	}
	action mouse_exit{
		ask simulation {do mouse_exit;}
	}
	
	
	output synchronized:true{
		layout horizontal([0::50, 1::50]) navigator:false editors:false parameters:false consoles:false tray:false;
		display logic type:2d toolbar:true {
			grid game_map border:#black;
			species player;
			species baddy;
			event #arrow_up 	action:up;
			event #arrow_down 	action:down;
			event #arrow_left 	action:left;
			event #arrow_right 	action:right;
			//event mouse_move 	action:mouse_move;{ask simulation {do mouse_move;}}
			event #mouse_down	action:mouse_down;
			event #mouse_enter	action:mouse_enter;
			event #mouse_exit	action:mouse_exit;
		}
		display rendering type:3d axes:false  toolbar:false {
		camera 'default' location: {50.0,50.0022,127.6281} target: {50.0,50.0,0.0} locked:true;			
		species player aspect:eye_of_the_beholder;	
			
			graphics g{	
				draw "fps: " + mean(fps) with_precision 1 at:{0,-1} color:#red font:font("helvetica",14, #bold);					
			}
		}
	}
}